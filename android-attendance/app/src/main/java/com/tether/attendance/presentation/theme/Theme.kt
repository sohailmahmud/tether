package com.tether.attendance.presentation.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors =
    lightColorScheme(
        primary = BrandBlue,
        onPrimary = Color.White,
        secondary = BrandNavy,
        background = CanvasLight,
        surface = Color.White,
        onSurfaceVariant = SlateText,
        outlineVariant = SlateLine,
        error = OutOfRangeRed,
    )

private val DarkColors =
    darkColorScheme(
        primary = BrandBlueDark,
        secondary = BrandBlueDark,
        background = CanvasDark,
        surface = SurfaceDark,
        onSurfaceVariant = SlateTextDark,
        outlineVariant = SlateLineDark,
        error = OutOfRangeRedDark,
    )

/**
 * App theme. Dynamic (wallpaper) colour is deliberately not used so the screen
 * keeps the reference design's palette on every device.
 */
@Composable
fun TetherTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
