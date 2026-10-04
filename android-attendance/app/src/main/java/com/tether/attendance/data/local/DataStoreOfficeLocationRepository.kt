package com.tether.attendance.data.local

import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.domain.repository.OfficeLocationRepository
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/**
 * Stores the office in Preferences DataStore: four values, written in one
 * transaction, read as a Flow so the screen updates as soon as a save lands.
 */
class DataStoreOfficeLocationRepository(private val dataStore: DataStore<Preferences>) :
    OfficeLocationRepository {

    override val officeLocation: Flow<OfficeLocation?> =
        dataStore.data
            .catch { e ->
                // An unreadable file is treated as "no office set"; the user can set it again.
                if (e !is IOException) throw e
                Log.w(TAG, "Office location could not be read", e)
                emit(emptyPreferences())
            }
            .map { it.toOfficeLocation() }
            .distinctUntilChanged()

    override suspend fun save(office: OfficeLocation) {
        dataStore.edit { it.writeOfficeLocation(office) }
    }

    private companion object {
        const val TAG = "OfficeLocationStore"
    }
}
