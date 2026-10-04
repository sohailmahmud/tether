package com.tether.attendance.presentation.attendance

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.tether.attendance.R
import com.tether.attendance.domain.model.AttendancePolicy
import com.tether.attendance.domain.model.AttendanceStatus
import com.tether.attendance.domain.model.Eligibility
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.presentation.theme.TetherTheme
import kotlin.math.ceil
import kotlin.math.roundToInt

/** Everything the indicator shows for one status, resolved from strings and theme. */
private data class RangeDisplay(
    val distance: String,
    /** Share of the ring filled: the radius divided by the distance, so it is full inside the geofence. */
    val progress: Float,
    val color: Color,
    val label: String?,
    val hint: String?,
    val accuracy: String?,
    val description: String,
    val action: Pair<String, () -> Unit>?,
)

/**
 * The live distance ring, range status and hint. Implements the brief's
 * real-time distance indicator ("You are 120m away from the office").
 */
@Composable
fun DistanceIndicator(
    isOfficeLoaded: Boolean,
    status: AttendanceStatus,
    onAllowLocation: () -> Unit,
    onTurnOnLocation: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val display = rangeDisplay(isOfficeLoaded, status, onAllowLocation, onTurnOnLocation)
    val progress by animateFloatAsState(display.progress, label = "rangeProgress")
    val color by animateColorAsState(display.color, label = "rangeColor")

    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        DistanceRing(display.distance, progress, color, display.description)
        if (display.label != null) {
            Spacer(Modifier.height(12.dp))
            StatusChip(display.label, color)
        }
        if (display.hint != null) {
            Spacer(Modifier.height(8.dp))
            Text(
                text = display.hint,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 24.dp),
            )
        }
        if (display.accuracy != null) {
            Spacer(Modifier.height(4.dp))
            Text(
                text = display.accuracy,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        display.action?.let { (label, onClick) ->
            Spacer(Modifier.height(12.dp))
            OutlinedButton(onClick = onClick, shape = RoundedCornerShape(12.dp)) { Text(label) }
        }
    }
}

@Composable
private fun rangeDisplay(
    isOfficeLoaded: Boolean,
    status: AttendanceStatus,
    onAllowLocation: () -> Unit,
    onTurnOnLocation: () -> Unit,
): RangeDisplay {
    val neutral = MaterialTheme.colorScheme.onSurfaceVariant
    val unknown = stringResource(R.string.distance_unknown)

    // Every state without a fix: no distance, neutral colour, an explanation and maybe a fix-it button.
    fun noFix(label: String?, hint: String?, action: Pair<String, () -> Unit>? = null) =
        RangeDisplay(
            distance = unknown,
            progress = 0f,
            color = neutral,
            label = label,
            hint = hint,
            accuracy = null,
            description = label ?: unknown,
            action = action,
        )

    if (!isOfficeLoaded) return noFix(label = null, hint = null)

    return when (status) {
        AttendanceStatus.OfficeNotSet ->
            noFix(
                stringResource(R.string.range_office_not_set),
                stringResource(R.string.range_hint_office_not_set),
            )
        is AttendanceStatus.Locating ->
            noFix(
                stringResource(R.string.range_locating),
                stringResource(R.string.range_hint_locating),
            )
        is AttendanceStatus.LocationUnavailable -> {
            val (label, hint, action) =
                when (status.error) {
                    LocationError.PermissionDenied ->
                        Triple(
                            stringResource(R.string.range_permission_needed),
                            stringResource(R.string.range_hint_permission_needed),
                            stringResource(R.string.action_allow_location) to onAllowLocation,
                        )
                    LocationError.LocationDisabled ->
                        Triple(
                            stringResource(R.string.range_location_off),
                            stringResource(R.string.range_hint_location_off),
                            stringResource(R.string.action_turn_on_location_long) to
                                onTurnOnLocation,
                        )
                    LocationError.Unavailable ->
                        Triple(
                            stringResource(R.string.range_no_signal),
                            stringResource(R.string.range_hint_no_signal),
                            null,
                        )
                }
            noFix(label, hint, action)
        }
        is AttendanceStatus.Measured -> measuredDisplay(status)
    }
}

@Composable
private fun measuredDisplay(status: AttendanceStatus.Measured): RangeDisplay {
    val distanceMeters = status.check.distanceMeters
    val distance = formatDistance(distanceMeters)
    val radius = AttendancePolicy.RADIUS_METERS
    val accuracyMeters = status.fix.accuracyMeters?.let { ceil(it).roundToInt() }
    val statusColors = TetherTheme.statusColors

    val (color, label, hint) =
        when (status.check.eligibility) {
            Eligibility.Eligible ->
                Triple(
                    statusColors.inRange,
                    stringResource(R.string.range_in_range),
                    stringResource(R.string.range_hint_in_range, distance),
                )
            Eligibility.OutOfRange ->
                Triple(
                    MaterialTheme.colorScheme.error,
                    stringResource(R.string.range_out_of_range),
                    stringResource(R.string.range_hint_out_of_range, distance, radius),
                )
            Eligibility.LowAccuracy ->
                Triple(
                    statusColors.weakSignal,
                    stringResource(R.string.range_weak_signal),
                    if (accuracyMeters == null) {
                        stringResource(R.string.range_hint_accuracy_unknown)
                    } else {
                        stringResource(
                            R.string.range_hint_weak_signal,
                            accuracyMeters,
                            AttendancePolicy.MAX_ACCURACY_METERS.roundToInt(),
                        )
                    },
                )
        }
    return RangeDisplay(
        distance = formatDistanceCompact(distanceMeters),
        progress = (radius / distanceMeters).toFloat().coerceIn(0f, 1f),
        color = color,
        label = label,
        hint = hint,
        accuracy = accuracyMeters?.let { stringResource(R.string.gps_accuracy, it) },
        description = stringResource(R.string.distance_description, distance),
        action = null,
    )
}

@Composable
private fun DistanceRing(distance: String, progress: Float, color: Color, description: String) {
    val track = MaterialTheme.colorScheme.outlineVariant
    Box(
        modifier =
        Modifier
            .size(128.dp)
            // Announces the distance as it changes, politely, for TalkBack users.
            .clearAndSetSemantics {
                contentDescription = description
                liveRegion = LiveRegionMode.Polite
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 8.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(size.width - stroke, size.height - stroke)
            drawCircle(color.copy(alpha = 0.06f), radius = size.minDimension / 2 - stroke)
            drawCircle(track, radius = (size.minDimension - stroke) / 2, style = Stroke(stroke))
            if (progress > 0f) {
                drawArc(
                    color = color,
                    startAngle = -90f,
                    sweepAngle = 360f * progress,
                    useCenter = false,
                    topLeft = Offset(inset, inset),
                    size = arcSize,
                    style = Stroke(stroke, cap = StrokeCap.Round),
                )
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = distance,
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = stringResource(R.string.distance_away).uppercase(),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun StatusChip(label: String, color: Color) {
    Surface(shape = CircleShape, color = color.copy(alpha = 0.12f)) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(color))
            Spacer(Modifier.width(6.dp))
            Text(
                text = label.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = color,
            )
        }
    }
}
