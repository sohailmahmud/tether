package com.tether.attendance.di

import android.content.Context
import com.google.android.gms.location.LocationServices
import com.tether.attendance.data.local.DataStoreOfficeLocationRepository
import com.tether.attendance.data.local.officeLocationDataStore
import com.tether.attendance.data.location.FusedLocationRepository
import com.tether.attendance.domain.repository.LocationRepository
import com.tether.attendance.domain.repository.OfficeLocationRepository
import com.tether.attendance.domain.usecase.SetOfficeLocationUseCase
import java.time.Clock

/**
 * Hand-written dependency graph, created once per process by the Application.
 * One screen and two repositories do not justify a DI framework.
 */
class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    val officeLocationRepository: OfficeLocationRepository by lazy {
        DataStoreOfficeLocationRepository(appContext.officeLocationDataStore)
    }

    val locationRepository: LocationRepository by lazy {
        FusedLocationRepository(
            appContext,
            LocationServices.getFusedLocationProviderClient(appContext),
        )
    }

    fun setOfficeLocationUseCase() =
        SetOfficeLocationUseCase(locationRepository, officeLocationRepository, Clock.systemUTC())
}
