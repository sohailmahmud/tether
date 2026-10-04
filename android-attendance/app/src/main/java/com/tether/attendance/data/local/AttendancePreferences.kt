package com.tether.attendance.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.tether.attendance.domain.model.AttendanceRecord

/** Separate from the office file: check-ins and the office location change independently. */
val Context.attendanceDataStore: DataStore<Preferences> by preferencesDataStore(name = "attendance")

private val MarkedAtKey = longPreferencesKey("last_marked_at_ms")
private val DistanceKey = doublePreferencesKey("last_distance_m")
private val AccuracyKey = floatPreferencesKey("last_accuracy_m")

/** Reads the last check-in, or null when none is stored or the record is partial. */
internal fun Preferences.toAttendanceRecord(): AttendanceRecord? {
    val markedAt = this[MarkedAtKey] ?: return null
    val distance = this[DistanceKey] ?: return null
    if (!distance.isFinite() || distance < 0) return null
    return AttendanceRecord(
        markedAtMillis = markedAt,
        distanceMeters = distance,
        accuracyMeters = this[AccuracyKey],
    )
}

internal fun MutablePreferences.writeAttendanceRecord(record: AttendanceRecord) {
    this[MarkedAtKey] = record.markedAtMillis
    this[DistanceKey] = record.distanceMeters
    val accuracy = record.accuracyMeters
    if (accuracy != null) this[AccuracyKey] = accuracy else remove(AccuracyKey)
}
