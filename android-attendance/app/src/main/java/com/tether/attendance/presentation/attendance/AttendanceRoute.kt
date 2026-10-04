package com.tether.attendance.presentation.attendance

import android.Manifest
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
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = LocalActivity.current

    // Requesting an already-granted permission returns at once without a dialog,
    // so every tap goes through here and the screen never checks permission itself.
    val permissionLauncher =
        rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { grants ->
            if (grants[Manifest.permission.ACCESS_FINE_LOCATION] == true) {
                viewModel.onSetOfficeLocation()
            } else {
                viewModel.onLocationPermissionDenied(
                    coarseGranted = grants[Manifest.permission.ACCESS_COARSE_LOCATION] == true,
                    // False after "don't ask again", when the system no longer shows the dialog.
                    canAskAgain =
                    activity?.let {
                        ActivityCompat.shouldShowRequestPermissionRationale(
                            it,
                            Manifest.permission.ACCESS_FINE_LOCATION,
                        )
                    } ?: true,
                )
            }
        }

    LifecycleResumeEffect(viewModel) {
        viewModel.onScreenResumed()
        onPauseOrDispose {}
    }

    AttendanceScreen(
        state = state,
        onSetOfficeLocation = { permissionLauncher.launch(LocationPermissions) },
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
    )
}

/** Opens a specific settings page, falling back to the main Settings app if a vendor build lacks it. */
private fun Context.openSettings(intent: Intent) {
    try {
        startActivity(intent)
    } catch (e: ActivityNotFoundException) {
        startActivity(Intent(Settings.ACTION_SETTINGS))
    }
}
