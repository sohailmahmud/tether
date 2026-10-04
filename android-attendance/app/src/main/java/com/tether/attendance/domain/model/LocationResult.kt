package com.tether.attendance.domain.model

/** Outcome of asking the device for its current position. */
sealed interface LocationResult {
    data class Success(val location: LocationData) : LocationResult

    data class Failure(val error: LocationError) : LocationResult
}

/** Why a location could not be obtained. */
enum class LocationError {
    /** Precise (fine) location permission is not granted. */
    PermissionDenied,

    /** Location services are switched off on the device. */
    LocationDisabled,

    /** Location is on and permitted, but no fix arrived in time. */
    Unavailable,
}
