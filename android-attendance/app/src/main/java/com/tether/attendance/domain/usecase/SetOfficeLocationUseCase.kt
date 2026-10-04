package com.tether.attendance.domain.usecase

import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.domain.repository.LocationRepository
import com.tether.attendance.domain.repository.OfficeLocationRepository
import java.io.IOException
import java.time.Clock

/** Takes a fresh fix of where the user is now and saves it as the office. */
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

    data object StorageFailed : SetOfficeLocationResult
}
