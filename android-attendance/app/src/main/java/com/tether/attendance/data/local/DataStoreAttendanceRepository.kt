package com.tether.attendance.data.local

import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import com.tether.attendance.domain.model.AttendanceRecord
import com.tether.attendance.domain.repository.AttendanceRepository
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Keeps the most recent check-in in Preferences DataStore. */
class DataStoreAttendanceRepository(private val dataStore: DataStore<Preferences>) :
    AttendanceRepository {

    override val lastAttendance: Flow<AttendanceRecord?> =
        dataStore.data
            .catch { e ->
                if (e !is IOException) throw e
                Log.w(TAG, "Attendance record could not be read", e)
                emit(emptyPreferences())
            }
            .map { it.toAttendanceRecord() }
            .distinctUntilChanged()

    override suspend fun save(record: AttendanceRecord) {
        dataStore.edit { it.writeAttendanceRecord(record) }
    }

    private companion object {
        const val TAG = "AttendanceStore"
    }
}
