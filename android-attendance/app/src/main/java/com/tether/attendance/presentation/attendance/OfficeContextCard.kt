package com.tether.attendance.presentation.attendance

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tether.attendance.R
import com.tether.attendance.domain.model.OfficeLocation
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.roundToInt

/** Step 1 of the screen: where the office is, and the button that sets it. */
@Composable
fun OfficeContextCard(
    office: OfficeLocation?,
    isOfficeLoaded: Boolean,
    isSettingOffice: Boolean,
    onSetOfficeLocation: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(16.dp)) {
            StepHeader(isOfficeSet = office != null)
            Spacer(Modifier.height(12.dp))
            MapPreview(
                office = office,
                modifier =
                Modifier
                    .fillMaxWidth()
                    .height(140.dp)
                    .clip(RoundedCornerShape(12.dp)),
            )
            Spacer(Modifier.height(12.dp))
            Text(
                text = stringResource(R.string.office_description),
                style = MaterialTheme.typography.bodyMedium,
            )
            if (office != null) {
                Spacer(Modifier.height(4.dp))
                OfficeDetails(office)
            }
            Spacer(Modifier.height(16.dp))
            SetOfficeButton(
                enabled = isOfficeLoaded && !isSettingOffice,
                isSettingOffice = isSettingOffice,
                onClick = onSetOfficeLocation,
            )
        }
    }
}

@Composable
private fun StepHeader(isOfficeSet: Boolean) {
    val statusDescription =
        stringResource(
            if (isOfficeSet) R.string.office_status_set else R.string.office_status_not_set,
        )
    val colors = MaterialTheme.colorScheme
    val dotColor = if (isOfficeSet) colors.primary else colors.outlineVariant
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = stringResource(R.string.office_step_label).uppercase(),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Box(
            Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(dotColor)
                .semantics { contentDescription = statusDescription },
        )
    }
}

/**
 * A drawn, map-like backdrop with the saved coordinates. Not a real map: a map
 * SDK needs an API key, which the brief neither provides nor requires.
 */
@Composable
private fun MapPreview(office: OfficeLocation?, modifier: Modifier = Modifier) {
    val isDark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val land = if (isDark) Color(0xFF243447) else Color(0xFFE7EFE3)
    val road = if (isDark) Color(0xFF34485E) else Color.White
    val water = MaterialTheme.colorScheme.primary.copy(alpha = 0.35f)
    val pin = MaterialTheme.colorScheme.onSurfaceVariant

    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(land)
            val roadWidth = 6.dp.toPx()
            listOf(0.3f, 0.68f).forEach { y ->
                drawLine(
                    road,
                    Offset(0f, size.height * y),
                    Offset(size.width, size.height * y),
                    roadWidth,
                )
            }
            listOf(0.22f, 0.74f).forEach { x ->
                drawLine(
                    road,
                    Offset(size.width * x, 0f),
                    Offset(size.width * x, size.height),
                    roadWidth,
                )
            }
            drawLine(
                water,
                Offset(0f, size.height * 0.9f),
                Offset(size.width, size.height * 0.15f),
                3.dp.toPx(),
            )
            if (office !=
                null
            ) {
                drawCircle(
                    pin,
                    radius = 3.dp.toPx(),
                    center =
                    center + Offset(0f, 22.dp.toPx()),
                )
            }
        }
        CoordinatesChip(office)
    }
}

@Composable
private fun CoordinatesChip(office: OfficeLocation?) {
    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 2.dp,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_location_on),
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(16.dp),
            )
            Spacer(Modifier.width(6.dp))
            Text(
                text =
                if (office == null) {
                    stringResource(R.string.office_not_set_chip)
                } else {
                    stringResource(
                        R.string.office_coordinates,
                        office.latitude.formatCoordinate(),
                        office.longitude.formatCoordinate(),
                    )
                },
                style = MaterialTheme.typography.labelMedium,
                fontFamily = FontFamily.Monospace,
            )
        }
    }
}

@Composable
private fun OfficeDetails(office: OfficeLocation) {
    val savedAt =
        remember(office.savedAtMillis) {
            DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
                .withZone(ZoneId.systemDefault())
                .format(Instant.ofEpochMilli(office.savedAtMillis))
        }
    val accuracy =
        office.accuracyMeters?.let {
            stringResource(R.string.office_accuracy, it.roundToInt().coerceAtLeast(1))
        }
            ?: stringResource(R.string.office_accuracy_unknown)
    Text(
        text = "$accuracy · ${stringResource(R.string.office_saved_at, savedAt)}",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun SetOfficeButton(enabled: Boolean, isSettingOffice: Boolean, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.fillMaxWidth().height(52.dp),
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(
            1.5.dp,
            MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 1f else 0.38f),
        ),
    ) {
        Row(
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (isSettingOffice) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text(
                    stringResource(R.string.setting_office_location),
                    fontWeight = FontWeight.SemiBold,
                )
            } else {
                Icon(
                    painter = painterResource(R.drawable.ic_add_circle_outline),
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.set_office_location), fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** Four decimal places is about 11 m: enough to recognise a location, matching the reference. */
private fun Double.formatCoordinate(): String = String.format(Locale.ROOT, "%.4f", this)
