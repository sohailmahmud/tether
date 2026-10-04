package com.tether.attendance.presentation.attendance

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.tether.attendance.R
import com.tether.attendance.domain.model.AttendanceCheck
import com.tether.attendance.domain.model.AttendanceRecord
import com.tether.attendance.domain.model.AttendanceStatus
import com.tether.attendance.domain.model.Eligibility
import com.tether.attendance.domain.model.LocationData
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.presentation.theme.TetherTheme

/** Callbacks from [AttendanceScreen]; grouped so the screen's signature stays readable. */
data class AttendanceActions(
    val onSetOfficeLocation: () -> Unit = {},
    val onMarkAttendance: () -> Unit = {},
    val onAllowLocation: () -> Unit = {},
    val onOpenAppSettings: () -> Unit = {},
    val onOpenLocationSettings: () -> Unit = {},
    val onDismissError: () -> Unit = {},
)

/**
 * Office setup and attendance on one screen, as the brief requires.
 * Stateless: renders [state] and reports user intent through [actions].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AttendanceScreen(
    state: AttendanceUiState,
    actions: AttendanceActions,
    modifier: Modifier = Modifier,
) {
    var confirmReplace by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.attendance_title),
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.secondary,
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { innerPadding ->
        Column(
            modifier =
            Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            state.error?.let { error ->
                ErrorBanner(
                    error = error,
                    action = error.action(actions),
                    onDismiss = actions.onDismissError,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            OfficeContextCard(
                office = state.officeLocation,
                isOfficeLoaded = state.isOfficeLoaded,
                isSettingOffice = state.isSettingOffice,
                onSetOfficeLocation = {
                    // Replacing moves the geofence, so a stray tap must not do it silently.
                    val hasOffice = state.officeLocation != null
                    if (hasOffice) confirmReplace = true else actions.onSetOfficeLocation()
                },
                modifier = Modifier.fillMaxWidth(),
            )
            DistanceIndicator(
                isOfficeLoaded = state.isOfficeLoaded,
                status = state.status,
                onAllowLocation = actions.onAllowLocation,
                onTurnOnLocation = actions.onOpenLocationSettings,
                modifier = Modifier.fillMaxWidth(),
            )
            MarkAttendanceSection(
                enabled = state.canMarkAttendance,
                isMarking = state.isMarkingAttendance,
                lastAttendance = state.lastAttendance,
                onMarkAttendance = actions.onMarkAttendance,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }

    if (confirmReplace) {
        AlertDialog(
            onDismissRequest = { confirmReplace = false },
            title = { Text(stringResource(R.string.replace_office_title)) },
            text = { Text(stringResource(R.string.replace_office_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmReplace = false
                        actions.onSetOfficeLocation()
                    },
                ) { Text(stringResource(R.string.replace_office_confirm)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    confirmReplace = false
                }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

private fun AttendanceError.action(actions: AttendanceActions): ErrorAction? = when (this) {
    AttendanceError.PermissionPermanentlyDenied,
    AttendanceError.PreciseLocationDenied,
    -> ErrorAction(R.string.action_open_settings, actions.onOpenAppSettings)
    AttendanceError.LocationDisabled -> ErrorAction(
        R.string.action_turn_on_location,
        actions.onOpenLocationSettings,
    )
    // Retrying is the main buttons' job; no separate action needed.
    AttendanceError.PermissionDenied,
    AttendanceError.LocationUnavailable,
    AttendanceError.OfficeSaveFailed,
    AttendanceError.NoLongerEligible,
    AttendanceError.AttendanceSaveFailed,
    -> null
}

private val PreviewOffice = OfficeLocation(23.7808, 90.4071, 8f, 1_790_000_000_000)

private fun previewMeasured(distance: Double, eligibility: Eligibility, accuracy: Float = 6f) =
    AttendanceStatus.Measured(
        office = PreviewOffice,
        fix = LocationData(23.7809, 90.4072, accuracy, 0L, 0L),
        check = AttendanceCheck(distance, eligibility),
    )

@Preview(showBackground = true, heightDp = 900)
@Composable
private fun AttendanceScreenOfficeNotSetPreview() {
    TetherTheme {
        AttendanceScreen(
            state = AttendanceUiState(isOfficeLoaded = true),
            actions = AttendanceActions(),
        )
    }
}

@Preview(showBackground = true, heightDp = 900)
@Composable
private fun AttendanceScreenOutOfRangePreview() {
    TetherTheme {
        AttendanceScreen(
            state = AttendanceUiState(
                isOfficeLoaded = true,
                status = previewMeasured(120.0, Eligibility.OutOfRange),
            ),
            actions = AttendanceActions(),
        )
    }
}

@Preview(showBackground = true, heightDp = 900)
@Composable
private fun AttendanceScreenInRangePreview() {
    TetherTheme {
        AttendanceScreen(
            state =
            AttendanceUiState(
                isOfficeLoaded = true,
                status = previewMeasured(12.0, Eligibility.Eligible),
                lastAttendance = AttendanceRecord(1_790_000_000_000, 9.0, 5f),
            ),
            actions = AttendanceActions(),
        )
    }
}
