package com.tether.attendance.domain.model

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Great-circle distance on a spherical Earth (haversine formula).
 *
 * Pure Kotlin so the attendance rule can be unit-tested without Android. Against
 * the WGS 84 ellipsoid the error is at most about 0.5%, i.e. under 0.3 m at the
 * 50 m geofence radius, well below GPS accuracy.
 */
object GeoDistance {
    /** IUGG mean Earth radius. */
    private const val EARTH_RADIUS_METERS = 6_371_008.8

    fun meters(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double,
    ): Double {
        val lat1 = Math.toRadians(fromLatitude)
        val lat2 = Math.toRadians(toLatitude)
        val dLat = lat2 - lat1
        val dLon = Math.toRadians(toLongitude - fromLongitude)
        val a =
            sin(dLat / 2).let { it * it } + cos(lat1) * cos(lat2) * sin(dLon / 2).let { it * it }
        // min() guards against floating-point rounding pushing a just above 1.
        return 2 * EARTH_RADIUS_METERS * asin(sqrt(min(1.0, a)))
    }
}
