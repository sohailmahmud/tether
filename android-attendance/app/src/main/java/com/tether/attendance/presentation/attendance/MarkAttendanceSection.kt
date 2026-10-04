package com.tether.attendance.presentation.attendance

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tether.attendance.R
import com.tether.attendance.domain.model.AttendancePolicy

/** The check-in area: a dashed panel with the Mark Attendance button. */
@Composable
fun MarkAttendanceSection(
    enabled: Boolean,
    onMarkAttendance: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dash = MaterialTheme.colorScheme.outlineVariant
    Column(
        modifier =
        modifier
            .drawBehind {
                val stroke = 1.5.dp.toPx()
                drawRoundRect(
                    color = dash,
                    cornerRadius = CornerRadius(16.dp.toPx()),
                    style = Stroke(
                        width = stroke,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 10f)),
                    ),
                )
            }
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (!enabled) {
            Icon(
                painter = painterResource(R.drawable.ic_lock_outline),
                contentDescription = stringResource(R.string.mark_attendance_locked),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(32.dp),
            )
            Spacer(Modifier.height(16.dp))
        }
        Button(
            onClick = onMarkAttendance,
            enabled = enabled,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(12.dp),
        ) {
            Text(stringResource(R.string.mark_attendance), fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(12.dp))
        Text(
            text = stringResource(
                R.string.mark_attendance_rule,
                AttendancePolicy.RADIUS_METERS,
            ).uppercase(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
