package com.tether.attendance.presentation.attendance

import java.util.Locale
import kotlin.math.ceil

/**
 * Whole metres, rounded up so the number shown always agrees with the
 * "within 50 m" rule: 50.0 m shows as 50 (in range) and 50.2 m as 51 (out).
 * Ordinary rounding would show "50m" for 50.4 m while the button stays locked.
 */
internal fun displayMeters(meters: Double): Int = ceil(meters).toInt()

/** Compact form for the ring: "120m", or "1.2km" from 1 km. */
internal fun formatDistanceCompact(meters: Double, locale: Locale = Locale.getDefault()): String {
    val whole = displayMeters(meters)
    return if (whole < 1_000) "${whole}m" else String.format(locale, "%.1fkm", meters / 1_000)
}

/** Sentence form: "120 m", or "1.2 km" from 1 km. */
internal fun formatDistance(meters: Double, locale: Locale = Locale.getDefault()): String {
    val whole = displayMeters(meters)
    return if (whole < 1_000) "$whole m" else String.format(locale, "%.1f km", meters / 1_000)
}
