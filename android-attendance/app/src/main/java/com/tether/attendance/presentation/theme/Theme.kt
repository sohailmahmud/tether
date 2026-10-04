package com.tether.attendance.presentation.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
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
        onPrimary = CanvasDark,
        secondary = BrandBlueDark,
        background = CanvasDark,
        surface = SurfaceDark,
        onSurfaceVariant = SlateTextDark,
        outlineVariant = SlateLineDark,
        error = OutOfRangeRedDark,
    )

/** Status colours Material 3 doesn't define. Out of range uses the scheme's `error`. */
@Immutable
data class StatusColors(val inRange: Color, val weakSignal: Color)

private val LightStatusColors = StatusColors(inRange = InRangeGreen, weakSignal = WeakSignalAmber)
private val DarkStatusColors =
    StatusColors(inRange = InRangeGreenDark, weakSignal = WeakSignalAmberDark)

private val LocalStatusColors = staticCompositionLocalOf { LightStatusColors }

/** Access as `TetherTheme.statusColors` inside [TetherTheme]. */
object TetherTheme {
    val statusColors: StatusColors
        @Composable @ReadOnlyComposable
        get() = LocalStatusColors.current
}

/**
 * App theme. Dynamic (wallpaper) colour is deliberately not used so the screen
 * keeps the reference design's palette on every device.
 */
@Composable
fun TetherTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    CompositionLocalProvider(
        LocalStatusColors provides if (darkTheme) DarkStatusColors else LightStatusColors,
    ) {
        MaterialTheme(
            colorScheme = if (darkTheme) DarkColors else LightColors,
            content = content,
        )
    }
}
