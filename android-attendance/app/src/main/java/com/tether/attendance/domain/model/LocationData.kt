package com.tether.attendance.domain.model

/**
 * A single location fix.
 *
 * @property accuracyMeters horizontal accuracy (68% confidence radius) reported
 *   by the provider, or null when the provider did not report one.
 * @property timestampMillis UTC time of the fix, in epoch milliseconds.
 * @property elapsedRealtimeMillis when the fix was taken on the device's
 *   monotonic clock (time since boot). Used to judge a fix's age, because the
 *   wall clock can be changed by the user or by network time updates.
 */
data class LocationData(
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Float?,
    val timestampMillis: Long,
    val elapsedRealtimeMillis: Long,
)
