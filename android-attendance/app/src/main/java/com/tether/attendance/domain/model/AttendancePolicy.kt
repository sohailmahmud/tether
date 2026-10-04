package com.tether.attendance.domain.model

/**
 * Business rules for attendance. The only place the geofence rules are defined:
 * the screen and [com.tether.attendance.domain.usecase.MarkAttendanceUseCase]
 * both ask [evaluate] rather than comparing distances themselves.
 */
object AttendancePolicy {
    /** Attendance is allowed only within this distance of the office (assessment requirement). */
    const val RADIUS_METERS = 50

    /**
     * Fixes less precise than this are not trusted for check-in, or to set the
     * office from.
     *
     * Not from the assessment, which asks for "high accuracy" without a number.
     * Chosen equal to the radius: a fix whose uncertainty is larger than the
     * geofence itself cannot tell inside from outside.
     */
    const val MAX_ACCURACY_METERS = 50f

    /**
     * A fix older than this no longer counts: the screen shows "no GPS signal"
     * and check-in is refused. Live updates arrive every 2 s, so 15 s without
     * one means the signal is really gone, not just a brief gap, and the user
     * may have moved since.
     */
    const val MAX_FIX_AGE_MILLIS = 15_000L

    fun evaluate(office: OfficeLocation, fix: LocationData): AttendanceCheck {
        val distance =
            GeoDistance.meters(office.latitude, office.longitude, fix.latitude, fix.longitude)
        val eligibility =
            when {
                // Clearly outside is reported as such even on a poor fix: moving closer is the fix.
                distance > RADIUS_METERS -> Eligibility.OutOfRange
                !isPreciseEnough(fix) -> Eligibility.LowAccuracy
                else -> Eligibility.Eligible
            }
        return AttendanceCheck(distanceMeters = distance, eligibility = eligibility)
    }

    /** Whether [fix] is within [MAX_ACCURACY_METERS]. A fix of unknown accuracy is not. */
    fun isPreciseEnough(fix: LocationData): Boolean {
        val accuracy = fix.accuracyMeters
        return accuracy != null && accuracy <= MAX_ACCURACY_METERS
    }
}

/** Result of applying [AttendancePolicy] to one fix. */
data class AttendanceCheck(val distanceMeters: Double, val eligibility: Eligibility)

enum class Eligibility {
    Eligible,
    OutOfRange,

    /** Within range on paper, but the fix is too imprecise to rely on. */
    LowAccuracy,
}
