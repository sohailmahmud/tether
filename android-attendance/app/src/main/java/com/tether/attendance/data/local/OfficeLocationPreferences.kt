package com.tether.attendance.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.tether.attendance.domain.model.OfficeLocation

/** One DataStore per process for this file, as DataStore requires. */
val Context.officeLocationDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "office_location",
)

private val LatitudeKey = doublePreferencesKey("latitude")
private val LongitudeKey = doublePreferencesKey("longitude")
private val AccuracyKey = floatPreferencesKey("accuracy_m")
private val SavedAtKey = longPreferencesKey("saved_at_ms")

/** Reads the office, or null when it is missing, partial or out of range. */
internal fun Preferences.toOfficeLocation(): OfficeLocation? {
    val latitude = this[LatitudeKey] ?: return null
    val longitude = this[LongitudeKey] ?: return null
    val savedAt = this[SavedAtKey] ?: return null
    if (!OfficeLocation.isValidCoordinate(latitude, longitude)) return null
    return OfficeLocation(
        latitude = latitude,
        longitude = longitude,
        accuracyMeters = this[AccuracyKey],
        savedAtMillis = savedAt,
    )
}

/** Writes every field, so a later read never mixes old and new values. */
internal fun MutablePreferences.writeOfficeLocation(office: OfficeLocation) {
    this[LatitudeKey] = office.latitude
    this[LongitudeKey] = office.longitude
    this[SavedAtKey] = office.savedAtMillis
    val accuracy = office.accuracyMeters
    if (accuracy != null) this[AccuracyKey] = accuracy else remove(AccuracyKey)
}
