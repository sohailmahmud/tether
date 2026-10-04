package com.tether.attendance.domain.model

/** Business rules for attendance. The only place the geofence radius is defined. */
object AttendancePolicy {
    /** Attendance is allowed only within this distance of the office (assessment requirement). */
    const val RADIUS_METERS = 50
}
