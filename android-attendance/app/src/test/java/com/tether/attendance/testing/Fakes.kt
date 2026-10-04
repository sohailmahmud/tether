package com.tether.attendance.testing

import com.tether.attendance.domain.model.AttendanceRecord
import com.tether.attendance.domain.model.LocationData
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.domain.repository.AttendanceRepository
import com.tether.attendance.domain.repository.LocationRepository
import com.tether.attendance.domain.repository.OfficeLocationRepository
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onStart

/** Metres per degree of latitude on the sphere GeoDistance uses. */
const val METERS_PER_DEGREE_LATITUDE = 6_371_008.8 * Math.PI / 180

val SampleOffice = OfficeLocation(23.7808, 90.4071, accuracyMeters = 5f, savedAtMillis = 10L)

val SampleFix =
    LocationData(
        latitude = 23.7808,
        longitude = 90.4071,
        accuracyMeters = 8f,
        timestampMillis = 1_000L,
        elapsedRealtimeMillis = 100_000L,
    )

/** A fix [metersNorth] due north of [office]; on a meridian the distance is exact. */
fun fixNorthOf(
    office: OfficeLocation,
    metersNorth: Double,
    accuracyMeters: Float? = 8f,
    elapsedRealtimeMillis: Long = SampleFix.elapsedRealtimeMillis,
) = SampleFix.copy(
    latitude = office.latitude + metersNorth / METERS_PER_DEGREE_LATITUDE,
    longitude = office.longitude,
    accuracyMeters = accuracyMeters,
    elapsedRealtimeMillis = elapsedRealtimeMillis,
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

    /** Live updates delivered to every active tracker. */
    val updates = MutableSharedFlow<LocationResult>(extraBufferCapacity = 16)

    /** Number of locationUpdates() collections currently running. */
    var activeTrackers = 0
        private set
    var trackingStarts = 0
        private set

    override fun hasLocationPermission() = hasPermission

    override fun isLocationEnabled() = locationEnabled

    override suspend fun getCurrentLocation(): LocationResult {
        requestCount++
        gate?.await()
        return result
    }

    // Mirrors FusedLocationRepository: without permission, report it once and stay open.
    override fun locationUpdates(): Flow<LocationResult> = flow {
        if (!hasPermission) {
            emit(LocationResult.Failure(LocationError.PermissionDenied))
            awaitCancellation()
        }
        emitAll(updates)
    }.onStart {
        activeTrackers++
        trackingStarts++
    }.onCompletion { activeTrackers-- }
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

class FakeAttendanceRepository : AttendanceRepository {
    val stored = MutableStateFlow<AttendanceRecord?>(null)
    var failSave = false

    /** When set, save() suspends until it completes, simulating slow storage. */
    var gate: CompletableDeferred<Unit>? = null
    var saveCount = 0
        private set

    override val lastAttendance = stored

    override suspend fun save(record: AttendanceRecord) {
        saveCount++
        gate?.await()
        if (failSave) throw IOException("disk full")
        stored.value = record
    }
}
