package com.tether.attendance.presentation.attendance

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.ActivityCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

/** Both are requested together: Android 12+ rejects a request for fine location alone. */
private val LocationPermissions =
    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

/**
 * Connects [AttendanceScreen] to [AttendanceViewModel] and to the Android pieces
 * the ViewModel must not touch: the permission dialog and settings screens.
 */
@Composable
fun AttendanceRoute(
    viewModel: AttendanceViewModel = viewModel(factory = AttendanceViewModel.Factory),
) {
    // Collected only while the screen is at least STARTED, which is what stops
    // location updates when the app goes to the background.
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = LocalActivity.current

    // Requesting an already-granted permission returns at once without a dialog,
    // so every location action goes through a request and the screen never checks
    // permission itself. Two launchers, because the follow-up differs.
    val setOfficePermission =
        rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { grants ->
            if (grants.isFineGranted()) {
                viewModel.onSetOfficeLocation()
            } else {
                viewModel.onLocationPermissionDenied(
                    grants.isCoarseGranted(),
                    activity.canAskAgain(),
                )
            }
        }
    val trackingPermission =
        rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { grants ->
            if (grants.isFineGranted()) {
                viewModel.onLocationPermissionGranted()
            } else {
                viewModel.onLocationPermissionDenied(
                    grants.isCoarseGranted(),
                    activity.canAskAgain(),
                )
            }
        }

    LifecycleResumeEffect(viewModel) {
        viewModel.onScreenResumed()
        onPauseOrDispose {}
    }

    AttendanceScreen(
        state = state,
        actions =
        AttendanceActions(
            onSetOfficeLocation = { setOfficePermission.launch(LocationPermissions) },
            onMarkAttendance = viewModel::onMarkAttendance,
            onAllowLocation = { trackingPermission.launch(LocationPermissions) },
            onOpenAppSettings = {
                context.openSettings(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", context.packageName, null),
                    ),
                )
            },
            onOpenLocationSettings = {
                context.openSettings(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            },
            onDismissError = viewModel::onErrorDismissed,
        ),
    )
}

private fun Map<String, Boolean>.isFineGranted() =
    this[Manifest.permission.ACCESS_FINE_LOCATION] == true

private fun Map<String, Boolean>.isCoarseGranted() =
    this[Manifest.permission.ACCESS_COARSE_LOCATION] == true

/** False after "don't ask again", when the system no longer shows the dialog. */
private fun Activity?.canAskAgain(): Boolean = this?.let {
    ActivityCompat.shouldShowRequestPermissionRationale(
        it,
        Manifest.permission.ACCESS_FINE_LOCATION,
    )
} ?: true

/** Opens a specific settings page, falling back to the main Settings app if a vendor build lacks it. */
private fun Context.openSettings(intent: Intent) {
    try {
        startActivity(intent)
    } catch (e: ActivityNotFoundException) {
        startActivity(Intent(Settings.ACTION_SETTINGS))
    }
}
