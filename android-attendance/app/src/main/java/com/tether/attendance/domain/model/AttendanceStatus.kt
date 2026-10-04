package com.tether.attendance.domain.model

/** Live attendance state: where the user stands relative to the office right now. */
sealed interface AttendanceStatus {
    val office: OfficeLocation?

    data object OfficeNotSet : AttendanceStatus {
        override val office: OfficeLocation? = null
    }

    /** Tracking has started; no fix yet. */
    data class Locating(override val office: OfficeLocation) : AttendanceStatus

    /** Tracking can't produce fixes (permission, location off, no signal). */
    data class LocationUnavailable(override val office: OfficeLocation, val error: LocationError) :
        AttendanceStatus

    data class Measured(
        override val office: OfficeLocation,
        val fix: LocationData,
        val check: AttendanceCheck,
    ) : AttendanceStatus
}
