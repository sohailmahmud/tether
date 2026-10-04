package com.tether.attendance.domain.usecase

import com.tether.attendance.domain.model.AttendancePolicy
import com.tether.attendance.domain.model.AttendanceStatus
import com.tether.attendance.domain.model.Eligibility
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.testing.FakeLocationRepository
import com.tether.attendance.testing.FakeOfficeLocationRepository
import com.tether.attendance.testing.SampleOffice
import com.tether.attendance.testing.fixNorthOf
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ObserveAttendanceStatusUseCaseTest {
    private val office = FakeOfficeLocationRepository()
    private val location = FakeLocationRepository()
    private val observe = ObserveAttendanceStatusUseCase(office, location)

    private fun TestScope.collectStatuses(): List<AttendanceStatus> {
        val statuses = mutableListOf<AttendanceStatus>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            observe().toList(statuses)
        }
        return statuses
    }

    @Test
    fun `without an office, location is not tracked`() = runTest {
        val statuses = collectStatuses()

        assertEquals(listOf(AttendanceStatus.OfficeNotSet), statuses)
        assertEquals(0, location.activeTrackers)
    }

    @Test
    fun `with an office, each fix is measured against it`() = runTest {
        office.stored.value = SampleOffice
        val statuses = collectStatuses()
        assertEquals(AttendanceStatus.Locating(SampleOffice), statuses.last())

        location.updates.emit(LocationResult.Success(fixNorthOf(SampleOffice, 120.0)))
        val far = statuses.last() as AttendanceStatus.Measured
        assertEquals(Eligibility.OutOfRange, far.check.eligibility)

        location.updates.emit(LocationResult.Success(fixNorthOf(SampleOffice, 10.0)))
        val near = statuses.last() as AttendanceStatus.Measured
        assertEquals(Eligibility.Eligible, near.check.eligibility)
        assertEquals(10.0, near.check.distanceMeters, 1e-6)
    }

    @Test
    fun `location problems become an unavailable status`() = runTest {
        office.stored.value = SampleOffice
        val statuses = collectStatuses()

        location.updates.emit(LocationResult.Failure(LocationError.LocationDisabled))

        assertEquals(
            AttendanceStatus.LocationUnavailable(SampleOffice, LocationError.LocationDisabled),
            statuses.last(),
        )
    }

    @Test
    fun `a new office restarts tracking against the new office`() = runTest {
        office.stored.value = SampleOffice
        val statuses = collectStatuses()
        val moved = SampleOffice.copy(latitude = SampleOffice.latitude + 0.01, savedAtMillis = 20L)

        office.stored.value = moved

        assertEquals(AttendanceStatus.Locating(moved), statuses.last())
        assertEquals(2, location.trackingStarts)
        assertEquals(1, location.activeTrackers)
    }

    @Test
    fun `clearing the office stops tracking`() = runTest {
        office.stored.value = SampleOffice
        collectStatuses()
        assertEquals(1, location.activeTrackers)

        office.stored.value = null

        assertEquals(0, location.activeTrackers)
    }

    @Test
    fun `a fix stops counting once no newer one arrives within the age limit`() = runTest {
        office.stored.value = SampleOffice
        val statuses = collectStatuses()
        location.updates.emit(LocationResult.Success(fixNorthOf(SampleOffice, 10.0)))

        advanceTimeBy(AttendancePolicy.MAX_FIX_AGE_MILLIS - 1)
        runCurrent()
        assertTrue(statuses.last() is AttendanceStatus.Measured)

        advanceTimeBy(2)
        runCurrent()
        assertEquals(
            AttendanceStatus.LocationUnavailable(SampleOffice, LocationError.Unavailable),
            statuses.last(),
        )
    }

    @Test
    fun `each new fix restarts the age limit`() = runTest {
        office.stored.value = SampleOffice
        val statuses = collectStatuses()

        repeat(3) {
            location.updates.emit(LocationResult.Success(fixNorthOf(SampleOffice, 10.0)))
            advanceTimeBy(AttendancePolicy.MAX_FIX_AGE_MILLIS - 1_000)
            runCurrent()
        }

        assertTrue(statuses.last() is AttendanceStatus.Measured)
    }

    @Test
    fun `no first fix within the age limit is reported as no signal`() = runTest {
        office.stored.value = SampleOffice
        val statuses = collectStatuses()

        advanceTimeBy(AttendancePolicy.MAX_FIX_AGE_MILLIS + 1)
        runCurrent()

        assertEquals(
            AttendanceStatus.LocationUnavailable(SampleOffice, LocationError.Unavailable),
            statuses.last(),
        )
    }

    @Test
    fun `signal returning after a gap is measured again`() = runTest {
        office.stored.value = SampleOffice
        val statuses = collectStatuses()
        advanceTimeBy(AttendancePolicy.MAX_FIX_AGE_MILLIS + 1)
        runCurrent()

        location.updates.emit(LocationResult.Success(fixNorthOf(SampleOffice, 10.0)))

        assertTrue(statuses.last() is AttendanceStatus.Measured)
    }
}
