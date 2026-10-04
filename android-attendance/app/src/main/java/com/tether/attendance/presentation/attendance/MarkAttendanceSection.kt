package com.tether.attendance.presentation.attendance

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.tether.attendance.R
import com.tether.attendance.domain.model.AttendancePolicy
import com.tether.attendance.domain.model.AttendanceRecord
import com.tether.attendance.presentation.theme.TetherTheme
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** The check-in area: a dashed panel with the Mark Attendance button and the last check-in. */
@Composable
fun MarkAttendanceSection(
    enabled: Boolean,
    isMarking: Boolean,
    lastAttendance: AttendanceRecord?,
    onMarkAttendance: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val inRange = TetherTheme.statusColors.inRange
    val border by animateColorAsState(
        if (enabled) inRange.copy(alpha = 0.6f) else MaterialTheme.colorScheme.outlineVariant,
        label = "panelBorder",
    )
    Column(
        modifier =
        modifier
            .drawBehind {
                drawRoundRect(
                    color = border,
                    cornerRadius = CornerRadius(16.dp.toPx()),
                    style =
                    Stroke(
                        width = 1.5.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(12f, 10f)),
                    ),
                )
            }
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            painter = painterResource(
                if (enabled) R.drawable.ic_lock_open else R.drawable.ic_lock_outline,
            ),
            contentDescription =
            stringResource(
                if (enabled) R.string.mark_attendance_unlocked else R.string.mark_attendance_locked,
            ),
            tint = if (enabled) inRange else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(32.dp),
        )
        Spacer(Modifier.height(16.dp))
        Button(
            onClick = onMarkAttendance,
            enabled = enabled,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(12.dp),
        ) {
            if (isMarking) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                    color = LocalContentColor.current,
                )
            } else {
                Text(stringResource(R.string.mark_attendance), fontWeight = FontWeight.SemiBold)
            }
        }
        Spacer(Modifier.height(12.dp))
        if (lastAttendance != null) {
            LastAttendance(lastAttendance)
        } else {
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
}

@Composable
private fun LastAttendance(record: AttendanceRecord) {
    val markedAt =
        remember(record.markedAtMillis) {
            val zone = ZoneId.systemDefault()
            val dateTime = Instant.ofEpochMilli(record.markedAtMillis).atZone(zone)
            val isToday = dateTime.toLocalDate() == LocalDate.now(zone)
            val formatter =
                if (isToday) {
                    DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
                } else {
                    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
                }
            isToday to formatter.format(dateTime)
        }
    val (isToday, time) = markedAt
    val text =
        if (isToday) {
            stringResource(R.string.last_marked_today, time, formatDistance(record.distanceMeters))
        } else {
            stringResource(R.string.last_marked, time, formatDistance(record.distanceMeters))
        }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            painter = painterResource(R.drawable.ic_check_circle),
            contentDescription = null,
            tint = TetherTheme.statusColors.inRange,
            modifier = Modifier.size(16.dp),
        )
        Spacer(Modifier.width(6.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}
