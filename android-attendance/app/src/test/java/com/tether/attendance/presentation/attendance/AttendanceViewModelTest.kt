package com.tether.attendance.presentation.attendance

import com.tether.attendance.domain.model.AttendanceStatus
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.domain.usecase.MarkAttendanceUseCase
import com.tether.attendance.domain.usecase.ObserveAttendanceStatusUseCase
import com.tether.attendance.domain.usecase.SetOfficeLocationUseCase
import com.tether.attendance.testing.FakeAttendanceRepository
import com.tether.attendance.testing.FakeLocationRepository
import com.tether.attendance.testing.FakeOfficeLocationRepository
import com.tether.attendance.testing.MainDispatcherRule
import com.tether.attendance.testing.SampleFix
import com.tether.attendance.testing.SampleOffice
import com.tether.attendance.testing.fixNorthOf
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AttendanceViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val now = Instant.ofEpochMilli(1_790_000_000_000)
    private val clock = Clock.fixed(now, ZoneOffset.UTC)
    private val location = FakeLocationRepository()
    private val office = FakeOfficeLocationRepository()
    private val attendance = FakeAttendanceRepository()
    private var elapsedRealtime = SampleFix.elapsedRealtimeMillis + 1_000

    private fun createViewModel() = AttendanceViewModel(
        observeAttendanceStatus = ObserveAttendanceStatusUseCase(office, location),
        attendanceRepository = attendance,
        locationRepository = location,
        setOfficeLocation = SetOfficeLocationUseCase(location, office, clock),
        markAttendance = MarkAttendanceUseCase(attendance, clock) { elapsedRealtime },
    )

    /** Collects like the screen does: the state only updates while someone is subscribed. */
    private fun TestScope.subscribe(viewModel: AttendanceViewModel): Job {
        val job = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect {}
        }
        runCurrent()
        return job
    }

    private suspend fun TestScope.emitFix(metersFromOffice: Double, accuracy: Float? = 8f) {
        location.updates.emit(
            LocationResult.Success(fixNorthOf(SampleOffice, metersFromOffice, accuracy)),
        )
        runCurrent()
    }

    // --- Loading and live distance ---

    @Test
    fun `nothing is shown as loaded until storage is read`() = runTest {
        val viewModel = createViewModel()
        assertFalse(viewModel.uiState.value.isOfficeLoaded)

        subscribe(viewModel)

        assertTrue(viewModel.uiState.value.isOfficeLoaded)
        assertEquals(AttendanceStatus.OfficeNotSet, viewModel.uiState.value.status)
    }

    @Test
    fun `a fix inside 50 m enables Mark Attendance`() = runTest {
        office.stored.value = SampleOffice
        val viewModel = createViewModel()
        subscribe(viewModel)

        emitFix(12.0)

        val state = viewModel.uiState.value
        assertTrue(state.isWithinRadius)
        assertTrue(state.canMarkAttendance)
        assertEquals(12.0, state.distanceMeters!!, 1e-6)
    }

    @Test
    fun `the distance updates live and Mark Attendance locks again outside 50 m`() = runTest {
        office.stored.value = SampleOffice
        val viewModel = createViewModel()
        subscribe(viewModel)
        emitFix(12.0)

        emitFix(120.0)

        val state = viewModel.uiState.value
        assertEquals(120.0, state.distanceMeters!!, 1e-6)
        assertFalse(state.isWithinRadius)
        assertFalse(state.canMarkAttendance)
    }

    @Test
    fun `a poor fix inside 50 m does not enable Mark Attendance`() = runTest {
        office.stored.value = SampleOffice
        val viewModel = createViewModel()
        subscribe(viewModel)

        emitFix(12.0, accuracy = 80f)

        assertFalse(viewModel.uiState.value.canMarkAttendance)
    }

    @Test
    fun `location updates stop 5 s after the screen stops collecting, restart on return`() =
        runTest {
            office.stored.value = SampleOffice
            val viewModel = createViewModel()
            val screen = subscribe(viewModel)
            assertEquals(1, location.activeTrackers)

            screen.cancel()
            advanceTimeBy(4_000)
            runCurrent()
            assertEquals("kept through a rotation-length gap", 1, location.activeTrackers)
            advanceTimeBy(1_001)
            runCurrent()
            assertEquals(0, location.activeTrackers)

            subscribe(viewModel)
            assertEquals(1, location.activeTrackers)
        }

    // --- Set Office Location ---

    @Test
    fun `setting the office shows progress, then tracks against the new office`() = runTest {
        val gate = CompletableDeferred<Unit>()
        location.gate = gate
        val viewModel = createViewModel()
        subscribe(viewModel)

        viewModel.onSetOfficeLocation()
        runCurrent()
        assertTrue(viewModel.uiState.value.isSettingOffice)
        gate.complete(Unit)
        runCurrent()

        val state = viewModel.uiState.value
        assertFalse(state.isSettingOffice)
        assertNull(state.error)
        assertEquals(SampleFix.latitude, state.officeLocation!!.latitude, 0.0)
        assertTrue(state.status is AttendanceStatus.Locating)
    }

    @Test
    fun `each location failure while setting the office maps to its own error`() = runTest {
        val viewModel = createViewModel()
        subscribe(viewModel)
        val expected =
            mapOf(
                LocationError.PermissionDenied to AttendanceError.PermissionDenied,
                LocationError.LocationDisabled to AttendanceError.LocationDisabled,
                LocationError.Unavailable to AttendanceError.LocationUnavailable,
            )

        expected.forEach { (locationError, uiError) ->
            location.result = LocationResult.Failure(locationError)
            viewModel.onSetOfficeLocation()
            runCurrent()

            assertEquals(uiError, viewModel.uiState.value.error)
            assertFalse(viewModel.uiState.value.isSettingOffice)
        }
        assertNull(office.stored.value)
    }

    @Test
    fun `office storage failure shows an error and keeps the previous office`() = runTest {
        office.stored.value = SampleOffice
        office.failSave = true
        val viewModel = createViewModel()
        subscribe(viewModel)

        viewModel.onSetOfficeLocation()
        runCurrent()

        assertEquals(AttendanceError.OfficeSaveFailed, viewModel.uiState.value.error)
        assertEquals(SampleOffice, viewModel.uiState.value.officeLocation)
    }

    @Test
    fun `a second Set tap while a fix is in progress starts no second request`() = runTest {
        val gate = CompletableDeferred<Unit>()
        location.gate = gate
        val viewModel = createViewModel()
        subscribe(viewModel)

        viewModel.onSetOfficeLocation()
        runCurrent()
        viewModel.onSetOfficeLocation()
        runCurrent()
        assertEquals(1, location.requestCount)

        gate.complete(Unit)
        runCurrent()
        assertFalse(viewModel.uiState.value.isSettingOffice)
    }

    @Test
    fun `a new attempt clears the previous error`() = runTest {
        location.result = LocationResult.Failure(LocationError.Unavailable)
        val viewModel = createViewModel()
        subscribe(viewModel)
        viewModel.onSetOfficeLocation()
        runCurrent()

        location.result = LocationResult.Success(SampleFix)
        viewModel.onSetOfficeLocation()
        runCurrent()

        assertNull(viewModel.uiState.value.error)
    }

    // --- Mark Attendance ---

    @Test
    fun `marking attendance in range saves and shows the check-in`() = runTest {
        office.stored.value = SampleOffice
        val viewModel = createViewModel()
        subscribe(viewModel)
        emitFix(12.0)

        viewModel.onMarkAttendance()
        runCurrent()

        val state = viewModel.uiState.value
        assertNull(state.error)
        assertFalse(state.isMarkingAttendance)
        assertEquals(now.toEpochMilli(), state.lastAttendance!!.markedAtMillis)
    }

    @Test
    fun `marking with a fix that went stale is refused`() = runTest {
        office.stored.value = SampleOffice
        val viewModel = createViewModel()
        subscribe(viewModel)
        emitFix(12.0)
        elapsedRealtime = SampleFix.elapsedRealtimeMillis + 31_000

        viewModel.onMarkAttendance()
        runCurrent()

        assertEquals(AttendanceError.NoLongerEligible, viewModel.uiState.value.error)
        assertNull(attendance.stored.value)
    }

    @Test
    fun `attendance storage failure shows an error`() = runTest {
        office.stored.value = SampleOffice
        attendance.failSave = true
        val viewModel = createViewModel()
        subscribe(viewModel)
        emitFix(12.0)

        viewModel.onMarkAttendance()
        runCurrent()

        assertEquals(AttendanceError.AttendanceSaveFailed, viewModel.uiState.value.error)
    }

    @Test
    fun `a second Mark tap while saving starts no second save`() = runTest {
        office.stored.value = SampleOffice
        val gate = CompletableDeferred<Unit>()
        attendance.gate = gate
        val viewModel = createViewModel()
        subscribe(viewModel)
        emitFix(12.0)

        viewModel.onMarkAttendance()
        runCurrent()
        assertTrue(viewModel.uiState.value.isMarkingAttendance)
        assertFalse(viewModel.uiState.value.canMarkAttendance)
        viewModel.onMarkAttendance()
        runCurrent()
        assertEquals(1, attendance.saveCount)

        gate.complete(Unit)
        runCurrent()
        assertFalse(viewModel.uiState.value.isMarkingAttendance)
    }

    @Test
    fun `Mark Attendance does nothing before there is a measurement`() = runTest {
        office.stored.value = SampleOffice
        val viewModel = createViewModel()
        subscribe(viewModel)

        viewModel.onMarkAttendance()
        runCurrent()

        assertEquals(0, attendance.saveCount)
    }

    // --- Permissions and resume ---

    @Test
    fun `granting permission from the distance prompt starts tracking`() = runTest {
        office.stored.value = SampleOffice
        location.hasPermission = false
        val viewModel = createViewModel()
        subscribe(viewModel)
        assertEquals(
            AttendanceStatus.LocationUnavailable(SampleOffice, LocationError.PermissionDenied),
            viewModel.uiState.value.status,
        )

        location.hasPermission = true
        viewModel.onLocationPermissionGranted()
        runCurrent()
        emitFix(12.0)

        assertTrue(viewModel.uiState.value.isWithinRadius)
    }

    @Test
    fun `returning from settings with permission granted restarts tracking`() = runTest {
        office.stored.value = SampleOffice
        location.hasPermission = false
        val viewModel = createViewModel()
        subscribe(viewModel)

        location.hasPermission = true
        viewModel.onScreenResumed()
        runCurrent()

        assertEquals(AttendanceStatus.Locating(SampleOffice), viewModel.uiState.value.status)
        assertEquals(2, location.trackingStarts)
    }

    @Test
    fun `resuming while tracking works does not restart it`() = runTest {
        office.stored.value = SampleOffice
        val viewModel = createViewModel()
        subscribe(viewModel)
        emitFix(12.0)

        viewModel.onScreenResumed()
        runCurrent()

        assertEquals(1, location.trackingStarts)
    }

    @Test
    fun `permission denial is classified by what was granted and whether Android will ask again`() =
        runTest {
            val viewModel = createViewModel()
            subscribe(viewModel)

            viewModel.onLocationPermissionDenied(coarseGranted = false, canAskAgain = true)
            runCurrent()
            assertEquals(AttendanceError.PermissionDenied, viewModel.uiState.value.error)

            viewModel.onLocationPermissionDenied(coarseGranted = false, canAskAgain = false)
            runCurrent()
            assertEquals(AttendanceError.PermissionPermanentlyDenied, viewModel.uiState.value.error)

            viewModel.onLocationPermissionDenied(coarseGranted = true, canAskAgain = false)
            runCurrent()
            assertEquals(AttendanceError.PreciseLocationDenied, viewModel.uiState.value.error)
        }

    @Test
    fun `returning from settings clears a permission error only once permission is granted`() =
        runTest {
            val viewModel = createViewModel()
            subscribe(viewModel)
            viewModel.onLocationPermissionDenied(coarseGranted = false, canAskAgain = false)

            location.hasPermission = false
            viewModel.onScreenResumed()
            runCurrent()
            assertEquals(AttendanceError.PermissionPermanentlyDenied, viewModel.uiState.value.error)

            location.hasPermission = true
            viewModel.onScreenResumed()
            runCurrent()
            assertNull(viewModel.uiState.value.error)
        }

    @Test
    fun `returning from settings clears the location-off error once location is on`() = runTest {
        location.result = LocationResult.Failure(LocationError.LocationDisabled)
        val viewModel = createViewModel()
        subscribe(viewModel)
        viewModel.onSetOfficeLocation()
        runCurrent()

        location.locationEnabled = false
        viewModel.onScreenResumed()
        runCurrent()
        assertEquals(AttendanceError.LocationDisabled, viewModel.uiState.value.error)

        location.locationEnabled = true
        viewModel.onScreenResumed()
        runCurrent()
        assertNull(viewModel.uiState.value.error)
    }

    @Test
    fun `dismissing clears the error`() = runTest {
        val viewModel = createViewModel()
        subscribe(viewModel)
        viewModel.onLocationPermissionDenied(coarseGranted = false, canAskAgain = true)

        viewModel.onErrorDismissed()
        runCurrent()

        assertNull(viewModel.uiState.value.error)
    }
}
