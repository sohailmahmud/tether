package com.tether.attendance.domain.repository

import com.tether.attendance.domain.model.OfficeLocation
import java.io.IOException
import kotlinx.coroutines.flow.Flow

/** Local storage for the office location. */
interface OfficeLocationRepository {
    /** The saved office, or null when none is set. Emits again on every change. */
    val officeLocation: Flow<OfficeLocation?>

    /** Saves [office], replacing any previous one. */
    @Throws(IOException::class)
    suspend fun save(office: OfficeLocation)
}
