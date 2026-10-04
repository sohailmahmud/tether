package com.tether.attendance.presentation.attendance

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class DistanceFormatTest {
    @Test
    fun `metres are rounded up so the label agrees with the 50 m rule`() {
        assertEquals(50, displayMeters(50.0))
        assertEquals(51, displayMeters(50.2))
        assertEquals(50, displayMeters(49.6))
        assertEquals(0, displayMeters(0.0))
    }

    @Test
    fun `compact form uses metres below 1 km and kilometres above`() {
        assertEquals("120m", formatDistanceCompact(120.0, Locale.ROOT))
        assertEquals("1.0km", formatDistanceCompact(999.5, Locale.ROOT))
        assertEquals("1.2km", formatDistanceCompact(1_234.0, Locale.ROOT))
    }

    @Test
    fun `sentence form separates the unit`() {
        assertEquals("120 m", formatDistance(119.2, Locale.ROOT))
        assertEquals("2.5 km", formatDistance(2_500.0, Locale.ROOT))
    }
}
