package com.tether.attendance.data.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult as FusedLocationResult
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.tether.attendance.domain.model.LocationData
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.domain.repository.LocationRepository
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.tasks.await

/** Gets the device position from Google Play services' fused location provider. */
class FusedLocationRepository(
    private val context: Context,
    private val client: FusedLocationProviderClient,
) : LocationRepository {

    private val locationManager = context.getSystemService(LocationManager::class.java)

    override fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    override fun isLocationEnabled(): Boolean =
        LocationManagerCompat.isLocationEnabled(locationManager)

    // MissingPermission: checked by hasLocationPermission() on the first line.
    // ExperimentalCoroutinesApi: await(CancellationTokenSource), which cancels the
    // platform request when the coroutine is cancelled.
    @SuppressLint("MissingPermission")
    @OptIn(ExperimentalCoroutinesApi::class)
    override suspend fun getCurrentLocation(): LocationResult {
        // Checked on every call, not just in the UI: permission can be revoked
        // from system settings while the app is in the background.
        if (!hasLocationPermission()) return LocationResult.Failure(LocationError.PermissionDenied)
        if (!isLocationEnabled()) return LocationResult.Failure(LocationError.LocationDisabled)

        val request =
            CurrentLocationRequest.Builder()
                .setPriority(Priority.PRIORITY_HIGH_ACCURACY)
                // A cached fix could be from somewhere else; the office must be where the user is now.
                .setMaxUpdateAgeMillis(0)
                .setDurationMillis(FIX_TIMEOUT_MILLIS)
                .build()

        // Cancelling the coroutine (e.g. the screen closes) cancels the platform request too.
        val cancellation = CancellationTokenSource()
        val location: Location? =
            try {
                client.getCurrentLocation(request, cancellation.token).await(cancellation)
            } catch (e: SecurityException) {
                return LocationResult.Failure(LocationError.PermissionDenied)
            } catch (e: ApiException) {
                Log.w(TAG, "Fused location request failed: status ${e.statusCode}")
                return LocationResult.Failure(LocationError.Unavailable)
            }

        // A null result means no fix arrived within the timeout.
        return location?.let { LocationResult.Success(it.toLocationData()) }
            ?: LocationResult.Failure(LocationError.Unavailable)
    }

    // MissingPermission: checked by hasLocationPermission() before requesting updates.
    @SuppressLint("MissingPermission")
    override fun locationUpdates(): Flow<LocationResult> = callbackFlow {
        if (!hasLocationPermission()) {
            // Stay open without updates; the ViewModel restarts tracking once permission is granted.
            send(LocationResult.Failure(LocationError.PermissionDenied))
            awaitClose()
            return@callbackFlow
        }
        // Updates are requested even when location is off: the provider starts
        // delivering by itself as soon as the user switches it back on.
        if (!isLocationEnabled()) send(LocationResult.Failure(LocationError.LocationDisabled))

        val callback =
            object : LocationCallback() {
                override fun onLocationResult(result: FusedLocationResult) {
                    result.lastLocation?.let {
                        trySend(LocationResult.Success(it.toLocationData()))
                    }
                }

                override fun onLocationAvailability(availability: LocationAvailability) {
                    // Indoors the provider reports brief "unavailable" gaps between good
                    // fixes, so that alone is not treated as signal loss: the use case
                    // detects it from fix age instead. Location being switched off is
                    // reported straight away.
                    if (!availability.isLocationAvailable && !isLocationEnabled()) {
                        trySend(LocationResult.Failure(LocationError.LocationDisabled))
                    }
                }
            }
        val request =
            LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, UPDATE_INTERVAL_MILLIS)
                .setMinUpdateIntervalMillis(MIN_UPDATE_INTERVAL_MILLIS)
                .build()
        try {
            client.requestLocationUpdates(request, callback, Looper.getMainLooper()).await()
        } catch (e: SecurityException) {
            send(LocationResult.Failure(LocationError.PermissionDenied))
        } catch (e: ApiException) {
            Log.w(TAG, "Location updates request failed: status ${e.statusCode}")
            send(LocationResult.Failure(LocationError.Unavailable))
        }
        awaitClose { client.removeLocationUpdates(callback) }
    }
        // Only the newest fix matters; a slow collector skips older ones.
        .conflate()

    private fun Location.toLocationData() = LocationData(
        latitude = latitude,
        longitude = longitude,
        accuracyMeters = if (hasAccuracy()) accuracy else null,
        timestampMillis = time,
        elapsedRealtimeMillis = TimeUnit.NANOSECONDS.toMillis(elapsedRealtimeNanos),
    )

    private companion object {
        const val TAG = "FusedLocation"

        /** Long enough for a cold GPS start outdoors; short enough that the user isn't left waiting. */
        const val FIX_TIMEOUT_MILLIS = 30_000L

        /** Fast enough for the distance to feel live while walking; only runs while the screen is visible. */
        const val UPDATE_INTERVAL_MILLIS = 2_000L
        const val MIN_UPDATE_INTERVAL_MILLIS = 1_000L
    }
}
