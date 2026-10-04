package com.tether.attendance.data.local

import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import com.tether.attendance.domain.model.OfficeLocation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OfficeLocationPreferencesTest {
    private val office =
        OfficeLocation(23.7808, 90.4071, accuracyMeters = 8f, savedAtMillis = 1_790_000_000_000)

    @Test
    fun `written office reads back unchanged`() {
        val prefs = mutablePreferencesOf().apply { writeOfficeLocation(office) }

        assertEquals(office, prefs.toOfficeLocation())
    }

    @Test
    fun `nothing stored reads as no office`() {
        assertNull(emptyPreferences().toOfficeLocation())
    }

    @Test
    fun `partially stored office reads as no office`() {
        val prefs = mutablePreferencesOf(
            doublePreferencesKey("latitude") to 23.78,
            longPreferencesKey("saved_at_ms") to 1L,
        )

        assertNull(prefs.toOfficeLocation())
    }

    @Test
    fun `out of range coordinates read as no office`() {
        val prefs = mutablePreferencesOf().apply {
            writeOfficeLocation(office.copy(latitude = 91.0))
        }

        assertNull(prefs.toOfficeLocation())
    }

    @Test
    fun `replacing with an unknown accuracy drops the old accuracy`() {
        val prefs = mutablePreferencesOf().apply { writeOfficeLocation(office) }

        prefs.writeOfficeLocation(office.copy(accuracyMeters = null))

        assertNull(prefs.toOfficeLocation()?.accuracyMeters)
    }
}
