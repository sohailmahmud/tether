package com.tether.attendance.domain.model

/** A successful check-in, kept locally. */
data class AttendanceRecord(
    val markedAtMillis: Long,
    val distanceMeters: Double,
    val accuracyMeters: Float?,
)
