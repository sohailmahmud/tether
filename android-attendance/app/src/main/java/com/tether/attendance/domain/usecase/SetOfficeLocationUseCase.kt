package com.tether.attendance.domain.usecase

import com.tether.attendance.domain.model.AttendancePolicy
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.domain.repository.LocationRepository
import com.tether.attendance.domain.repository.OfficeLocationRepository
import java.io.IOException
import java.time.Clock

/**
 * Takes a fresh fix of where the user is now and saves it as the office.
 *
 * The fix must meet the same accuracy rule as check-in: an office saved from
 * an imprecise fix would move the whole geofence by up to that error.
 */
class SetOfficeLocationUseCase(
    private val locationRepository: LocationRepository,
    private val officeLocationRepository: OfficeLocationRepository,
    private val clock: Clock,
) {
    suspend operator fun invoke(): SetOfficeLocationResult =
        when (val result = locationRepository.getCurrentLocation()) {
            is LocationResult.Failure -> SetOfficeLocationResult.LocationFailed(result.error)
            is LocationResult.Success -> {
                val fix = result.location
                if (!AttendancePolicy.isPreciseEnough(fix)) {
                    return SetOfficeLocationResult.LowAccuracy(fix.accuracyMeters)
                }
                val office =
                    OfficeLocation(
                        latitude = fix.latitude,
                        longitude = fix.longitude,
                        accuracyMeters = fix.accuracyMeters,
                        savedAtMillis = clock.millis(),
                    )
                try {
                    officeLocationRepository.save(office)
                    SetOfficeLocationResult.Saved(office)
                } catch (e: IOException) {
                    SetOfficeLocationResult.StorageFailed
                }
            }
        }
}

sealed interface SetOfficeLocationResult {
    data class Saved(val office: OfficeLocation) : SetOfficeLocationResult

    data class LocationFailed(val error: LocationError) : SetOfficeLocationResult

    /** The fix was less precise than [AttendancePolicy.MAX_ACCURACY_METERS]; nothing was saved. */
    data class LowAccuracy(val accuracyMeters: Float?) : SetOfficeLocationResult

    data object StorageFailed : SetOfficeLocationResult
}
