package com.tether.attendance.presentation.attendance

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.tether.attendance.R
import com.tether.attendance.domain.model.AttendancePolicy

/** The distance ring, range status and hint under Step 1. */
@Composable
fun DistanceIndicator(isOfficeSet: Boolean, modifier: Modifier = Modifier) {
    val status =
        stringResource(if (isOfficeSet) R.string.range_unknown else R.string.range_office_not_set)
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        DistanceRing(statusDescription = status)
        Spacer(Modifier.height(12.dp))
        Surface(shape = CircleShape, color = MaterialTheme.colorScheme.outlineVariant) {
            Text(
                text = status.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
            )
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text =
            if (isOfficeSet) {
                stringResource(R.string.range_hint, AttendancePolicy.RADIUS_METERS)
            } else {
                stringResource(R.string.range_hint_office_not_set)
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 24.dp),
        )
    }
}

@Composable
private fun DistanceRing(statusDescription: String) {
    val track = MaterialTheme.colorScheme.outlineVariant
    Box(
        modifier =
        Modifier
            .size(128.dp)
            .clearAndSetSemantics { contentDescription = statusDescription },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 8.dp.toPx()
            drawCircle(track, radius = (size.minDimension - stroke) / 2, style = Stroke(stroke))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = stringResource(R.string.distance_unknown),
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
