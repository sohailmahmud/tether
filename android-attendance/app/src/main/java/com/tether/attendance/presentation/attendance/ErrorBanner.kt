package com.tether.attendance.presentation.attendance

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tether.attendance.R

/** A fix the user can make from the banner, e.g. opening system settings. */
data class ErrorAction(@param:StringRes val label: Int, val onClick: () -> Unit)

/** Shows an [AttendanceError] until the user dismisses it or the cause is fixed. */
@Composable
fun ErrorBanner(
    error: AttendanceError,
    action: ErrorAction?,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        // Announced by TalkBack as soon as it appears.
        modifier = modifier.semantics { liveRegion = LiveRegionMode.Polite },
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
    ) {
        Column(Modifier.padding(start = 16.dp, top = 12.dp, end = 8.dp, bottom = 4.dp)) {
            Row {
                Icon(
                    painter = painterResource(R.drawable.ic_error_outline),
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(12.dp))
                Text(
                    text = stringResource(error.messageRes),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f).padding(end = 8.dp),
                )
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                // Banner text colour, not the theme's primary: blue on red is unreadable in dark mode.
                val buttonColors =
                    ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.onErrorContainer,
                    )
                TextButton(onClick = onDismiss, colors = buttonColors) {
                    Text(stringResource(R.string.action_dismiss))
                }
                if (action != null) {
                    TextButton(onClick = action.onClick, colors = buttonColors) {
                        Text(stringResource(action.label), fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

private val AttendanceError.messageRes: Int
    @StringRes get() =
        when (this) {
            AttendanceError.PermissionDenied -> R.string.error_permission_denied
            AttendanceError.PermissionPermanentlyDenied ->
                R.string.error_permission_permanently_denied
            AttendanceError.PreciseLocationDenied -> R.string.error_precise_location_denied
            AttendanceError.LocationDisabled -> R.string.error_location_disabled
            AttendanceError.LocationUnavailable -> R.string.error_location_unavailable
            AttendanceError.SaveFailed -> R.string.error_save_failed
        }
