package com.tether.attendance.data.local

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import com.tether.attendance.domain.model.AttendanceRecord
import com.tether.attendance.domain.model.OfficeLocation
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.job
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * The DataStore repositories against real files: what is saved survives a
 * restart, and an unreadable file degrades to "nothing saved" instead of
 * crashing. Robolectric provides android.util.Log for the error path.
 */
@RunWith(RobolectricTestRunner::class)
class DataStoreRepositoriesTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val scopes = mutableListOf<CoroutineScope>()
    private lateinit var officeFile: File
    private lateinit var attendanceFile: File

    @Before
    fun setUp() {
        officeFile = File(folder.root, "office_location.preferences_pb")
        attendanceFile = File(folder.root, "attendance.preferences_pb")
    }

    @After
    fun tearDown() {
        scopes.forEach { it.cancel() }
    }

    /** A DataStore on [file]. Cancelling its scope is how the app process "dies". */
    private fun open(file: File): Pair<DataStore<Preferences>, CoroutineScope> {
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob()).also(scopes::add)
        return PreferenceDataStoreFactory.create(scope = scope) { file } to scope
    }

    private val office =
        OfficeLocation(
            latitude = 40.7128,
            longitude = -74.006,
            accuracyMeters = 5f,
            savedAtMillis = 1_790_000_000_000,
        )

    @Test
    fun `the office reads as not set until one is saved, then as saved`() = runTest {
        val (store, _) = open(officeFile)
        val repository = DataStoreOfficeLocationRepository(store)

        assertNull(repository.officeLocation.first())
        repository.save(office)

        assertEquals(office, repository.officeLocation.first())
    }

    @Test
    fun `a saved office survives a restart`() = runTest {
        val (store, scope) = open(officeFile)
        DataStoreOfficeLocationRepository(store).save(office)
        // Waits until the store is fully closed; only then may the file be reopened.
        scope.coroutineContext.job.cancelAndJoin()

        val (reopened, _) = open(officeFile)

        assertEquals(office, DataStoreOfficeLocationRepository(reopened).officeLocation.first())
    }

    @Test
    fun `an unreadable office file reads as not set instead of crashing`() = runTest {
        officeFile.writeBytes(byteArrayOf(0x7f, 0x00, 0x13, 0x37))
        val (store, _) = open(officeFile)

        assertNull(DataStoreOfficeLocationRepository(store).officeLocation.first())
    }

    @Test
    fun `the last check-in survives a restart`() = runTest {
        val record =
            AttendanceRecord(
                markedAtMillis = 1_790_000_100_000,
                distanceMeters = 6.0,
                accuracyMeters = 5f,
            )
        val (store, scope) = open(attendanceFile)
        val repository = DataStoreAttendanceRepository(store)
        assertNull(repository.lastAttendance.first())
        repository.save(record)
        scope.coroutineContext.job.cancelAndJoin()

        val (reopened, _) = open(attendanceFile)

        assertEquals(record, DataStoreAttendanceRepository(reopened).lastAttendance.first())
    }

    @Test
    fun `an unreadable attendance file reads as never marked`() = runTest {
        attendanceFile.writeBytes(byteArrayOf(0x7f, 0x00, 0x13, 0x37))
        val (store, _) = open(attendanceFile)

        assertNull(DataStoreAttendanceRepository(store).lastAttendance.first())
    }
}
