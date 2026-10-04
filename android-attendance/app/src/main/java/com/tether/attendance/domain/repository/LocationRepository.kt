package com.tether.attendance.domain.repository

import com.tether.attendance.domain.model.LocationResult

/** Access to the device's position. */
interface LocationRepository {
    /** True when precise (fine) location permission is granted. */
    fun hasLocationPermission(): Boolean

    /** True when location services are switched on for the device. */
    fun isLocationEnabled(): Boolean

    /**
     * Requests one fresh, high-accuracy fix. Never throws for expected failures
     * (permission, location off, no fix); those come back as [LocationResult.Failure].
     */
    suspend fun getCurrentLocation(): LocationResult
}
