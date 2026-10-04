package com.tether.attendance.domain.usecase

import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.testing.FakeLocationRepository
import com.tether.attendance.testing.FakeOfficeLocationRepository
import com.tether.attendance.testing.SampleFix
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SetOfficeLocationUseCaseTest {
    private val now = Instant.ofEpochMilli(1_790_000_000_000)
    private val clock = Clock.fixed(now, ZoneOffset.UTC)
    private val location = FakeLocationRepository()
    private val office = FakeOfficeLocationRepository()
    private val setOfficeLocation = SetOfficeLocationUseCase(location, office, clock)

    @Test
    fun `saves the fresh fix with its accuracy and the current time`() = runTest {
        val result = setOfficeLocation()

        val expected =
            OfficeLocation(
                SampleFix.latitude,
                SampleFix.longitude,
                accuracyMeters = 8f,
                savedAtMillis = now.toEpochMilli(),
            )
        assertEquals(SetOfficeLocationResult.Saved(expected), result)
        assertEquals(expected, office.stored.value)
    }

    @Test
    fun `location failure is reported and nothing is saved`() = runTest {
        location.result = LocationResult.Failure(LocationError.LocationDisabled)

        val result = setOfficeLocation()

        assertEquals(SetOfficeLocationResult.LocationFailed(LocationError.LocationDisabled), result)
        assertNull(office.stored.value)
    }

    @Test
    fun `storage failure is reported instead of thrown`() = runTest {
        office.failSave = true

        assertEquals(SetOfficeLocationResult.StorageFailed, setOfficeLocation())
    }
}
