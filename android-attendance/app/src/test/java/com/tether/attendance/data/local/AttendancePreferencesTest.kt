package com.tether.attendance.data.local

import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import com.tether.attendance.domain.model.AttendanceRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AttendancePreferencesTest {
    private val record =
        AttendanceRecord(
            markedAtMillis = 1_790_000_000_000,
            distanceMeters = 12.5,
            accuracyMeters = 6f,
        )

    @Test
    fun `written record reads back unchanged`() {
        val prefs = mutablePreferencesOf().apply { writeAttendanceRecord(record) }

        assertEquals(record, prefs.toAttendanceRecord())
    }

    @Test
    fun `nothing stored reads as never marked`() {
        assertNull(emptyPreferences().toAttendanceRecord())
    }

    @Test
    fun `partial record reads as never marked`() {
        assertNull(
            mutablePreferencesOf(
                longPreferencesKey("last_marked_at_ms") to 1L,
            ).toAttendanceRecord(),
        )
    }

    @Test
    fun `replacing with an unknown accuracy drops the old accuracy`() {
        val prefs = mutablePreferencesOf().apply { writeAttendanceRecord(record) }

        prefs.writeAttendanceRecord(record.copy(accuracyMeters = null))

        assertNull(prefs.toAttendanceRecord()?.accuracyMeters)
    }
}
