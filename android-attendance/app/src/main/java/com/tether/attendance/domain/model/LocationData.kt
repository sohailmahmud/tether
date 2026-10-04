package com.tether.attendance.domain.model

/**
 * A single location fix.
 *
 * @property accuracyMeters horizontal accuracy (68% confidence radius) reported
 *   by the provider, or null when the provider did not report one.
 * @property timestampMillis UTC time of the fix, in epoch milliseconds.
 */
data class LocationData(
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Float?,
    val timestampMillis: Long,
)
