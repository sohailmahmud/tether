package com.tether.attendance.presentation.attendance

import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.domain.usecase.SetOfficeLocationUseCase
import com.tether.attendance.testing.FakeLocationRepository
import com.tether.attendance.testing.FakeOfficeLocationRepository
import com.tether.attendance.testing.MainDispatcherRule
import com.tether.attendance.testing.SampleFix
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
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

    private val savedOffice = OfficeLocation(1.0, 2.0, accuracyMeters = 5f, savedAtMillis = 10L)
    private val now = Instant.ofEpochMilli(1_790_000_000_000)
    private val location = FakeLocationRepository()
    private val office = FakeOfficeLocationRepository()

    private fun createViewModel() = AttendanceViewModel(
        officeLocationRepository = office,
        locationRepository = location,
        setOfficeLocation = SetOfficeLocationUseCase(
            location,
            office,
            Clock.fixed(now, ZoneOffset.UTC),
        ),
    )

    @Test
    fun `office is unknown until storage is read, then shows the saved office`() = runTest {
        office.stored.value = savedOffice
        val viewModel = createViewModel()
        assertFalse(viewModel.uiState.value.isOfficeLoaded)

        runCurrent()

        assertTrue(viewModel.uiState.value.isOfficeLoaded)
        assertEquals(savedOffice, viewModel.uiState.value.officeLocation)
    }

    @Test
    fun `setting the office shows progress, then the newly saved office`() = runTest {
        val viewModel = createViewModel()
        runCurrent()

        viewModel.onSetOfficeLocation()
        assertTrue(viewModel.uiState.value.isSettingOffice)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isSettingOffice)
        assertNull(state.error)
        assertEquals(SampleFix.latitude, state.officeLocation?.latitude)
        assertEquals(now.toEpochMilli(), state.officeLocation?.savedAtMillis)
    }

    @Test
    fun `each location failure maps to its own user-facing error`() = runTest {
        val viewModel = createViewModel()
        val expected =
            mapOf(
                LocationError.PermissionDenied to AttendanceError.PermissionDenied,
                LocationError.LocationDisabled to AttendanceError.LocationDisabled,
                LocationError.Unavailable to AttendanceError.LocationUnavailable,
            )

        expected.forEach { (locationError, uiError) ->
            location.result = LocationResult.Failure(locationError)
            viewModel.onSetOfficeLocation()
            advanceUntilIdle()

            assertEquals(uiError, viewModel.uiState.value.error)
            assertFalse(viewModel.uiState.value.isSettingOffice)
        }
        assertNull(office.stored.value)
    }

    @Test
    fun `storage failure shows an error and keeps the previous office`() = runTest {
        office.stored.value = savedOffice
        office.failSave = true
        val viewModel = createViewModel()

        viewModel.onSetOfficeLocation()
        advanceUntilIdle()

        assertEquals(AttendanceError.SaveFailed, viewModel.uiState.value.error)
        assertEquals(savedOffice, viewModel.uiState.value.officeLocation)
    }

    @Test
    fun `a second tap while a fix is in progress starts no second request`() = runTest {
        val gate = CompletableDeferred<Unit>()
        location.gate = gate
        val viewModel = createViewModel()

        viewModel.onSetOfficeLocation()
        runCurrent()
        viewModel.onSetOfficeLocation()
        runCurrent()
        assertEquals(1, location.requestCount)

        gate.complete(Unit)
        advanceUntilIdle()
        assertFalse(viewModel.uiState.value.isSettingOffice)
    }

    @Test
    fun `a new attempt clears the previous error`() = runTest {
        location.result = LocationResult.Failure(LocationError.Unavailable)
        val viewModel = createViewModel()
        viewModel.onSetOfficeLocation()
        advanceUntilIdle()

        location.result = LocationResult.Success(SampleFix)
        viewModel.onSetOfficeLocation()

        assertNull(viewModel.uiState.value.error)
    }

    @Test
    fun `permission denial is classified by what was granted and whether Android will ask again`() =
        runTest {
            val viewModel = createViewModel()

            viewModel.onLocationPermissionDenied(coarseGranted = false, canAskAgain = true)
            assertEquals(AttendanceError.PermissionDenied, viewModel.uiState.value.error)

            viewModel.onLocationPermissionDenied(coarseGranted = false, canAskAgain = false)
            assertEquals(AttendanceError.PermissionPermanentlyDenied, viewModel.uiState.value.error)

            viewModel.onLocationPermissionDenied(coarseGranted = true, canAskAgain = false)
            assertEquals(AttendanceError.PreciseLocationDenied, viewModel.uiState.value.error)
        }

    @Test
    fun `returning from settings clears a permission error only once permission is granted`() =
        runTest {
            val viewModel = createViewModel()
            viewModel.onLocationPermissionDenied(coarseGranted = false, canAskAgain = false)

            location.hasPermission = false
            viewModel.onScreenResumed()
            assertEquals(AttendanceError.PermissionPermanentlyDenied, viewModel.uiState.value.error)

            location.hasPermission = true
            viewModel.onScreenResumed()
            assertNull(viewModel.uiState.value.error)
        }

    @Test
    fun `returning from settings clears the location-off error once location is on`() = runTest {
        location.result = LocationResult.Failure(LocationError.LocationDisabled)
        val viewModel = createViewModel()
        viewModel.onSetOfficeLocation()
        advanceUntilIdle()

        location.locationEnabled = false
        viewModel.onScreenResumed()
        assertEquals(AttendanceError.LocationDisabled, viewModel.uiState.value.error)

        location.locationEnabled = true
        viewModel.onScreenResumed()
        assertNull(viewModel.uiState.value.error)
    }

    @Test
    fun `dismissing clears the error`() = runTest {
        val viewModel = createViewModel()
        viewModel.onLocationPermissionDenied(coarseGranted = false, canAskAgain = true)

        viewModel.onErrorDismissed()

        assertNull(viewModel.uiState.value.error)
    }
}
