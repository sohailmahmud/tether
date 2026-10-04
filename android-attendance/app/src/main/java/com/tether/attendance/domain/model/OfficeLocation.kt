package com.tether.attendance.domain.model

/**
 * The saved office position that attendance is checked against.
 *
 * @property accuracyMeters accuracy of the fix the office was set from, kept so
 *   the screen can show how trustworthy the saved point is.
 * @property savedAtMillis when the office was set, in epoch milliseconds.
 */
data class OfficeLocation(
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Float?,
    val savedAtMillis: Long,
) {
    companion object {
        /** True when the coordinates are finite and inside WGS 84 bounds. */
        fun isValidCoordinate(latitude: Double, longitude: Double): Boolean = latitude.isFinite() &&
            longitude.isFinite() &&
            latitude in -90.0..90.0 &&
            longitude in -180.0..180.0
    }
}
