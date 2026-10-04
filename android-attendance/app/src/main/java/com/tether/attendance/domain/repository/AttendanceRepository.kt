package com.tether.attendance.domain.repository

import com.tether.attendance.domain.model.AttendanceRecord
import java.io.IOException
import kotlinx.coroutines.flow.Flow

/** Local storage for check-ins. */
interface AttendanceRepository {
    /** The most recent check-in, or null if attendance was never marked. */
    val lastAttendance: Flow<AttendanceRecord?>

    @Throws(IOException::class)
    suspend fun save(record: AttendanceRecord)
}
