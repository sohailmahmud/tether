package com.tether.attendance.testing

import com.tether.attendance.domain.model.LocationData
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.domain.repository.LocationRepository
import com.tether.attendance.domain.repository.OfficeLocationRepository
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow

val SampleFix =
    LocationData(
        latitude = 23.7808,
        longitude = 90.4071,
        accuracyMeters = 8f,
        timestampMillis = 1_000L,
    )

class FakeLocationRepository(
    var result: LocationResult = LocationResult.Success(SampleFix),
    var hasPermission: Boolean = true,
    var locationEnabled: Boolean = true,
) : LocationRepository {
    /** When set, getCurrentLocation() suspends until it completes, simulating a slow fix. */
    var gate: CompletableDeferred<Unit>? = null
    var requestCount = 0
        private set

    override fun hasLocationPermission() = hasPermission

    override fun isLocationEnabled() = locationEnabled

    override suspend fun getCurrentLocation(): LocationResult {
        requestCount++
        gate?.await()
        return result
    }
}

class FakeOfficeLocationRepository(initial: OfficeLocation? = null) : OfficeLocationRepository {
    val stored = MutableStateFlow(initial)
    var failSave = false

    override val officeLocation = stored

    override suspend fun save(office: OfficeLocation) {
        if (failSave) throw IOException("disk full")
        stored.value = office
    }
}
