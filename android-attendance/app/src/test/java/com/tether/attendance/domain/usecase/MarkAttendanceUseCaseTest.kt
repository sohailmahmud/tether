package com.tether.attendance.domain.usecase

import com.tether.attendance.domain.model.AttendancePolicy
import com.tether.attendance.testing.FakeAttendanceRepository
import com.tether.attendance.testing.SampleOffice
import com.tether.attendance.testing.fixNorthOf
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MarkAttendanceUseCaseTest {
    private val now = Instant.ofEpochMilli(1_790_000_000_000)
    private val fixTakenAt = 100_000L
    private var elapsedRealtime = fixTakenAt + 2_000L
    private val repository = FakeAttendanceRepository()
    private val markAttendance =
        MarkAttendanceUseCase(repository, Clock.fixed(now, ZoneOffset.UTC)) { elapsedRealtime }

    private fun fixAt(meters: Double, accuracy: Float? = 8f) =
        fixNorthOf(SampleOffice, meters, accuracy, elapsedRealtimeMillis = fixTakenAt)

    @Test
    fun `an eligible fresh fix records the check-in`() = runTest {
        val result = markAttendance(SampleOffice, fixAt(12.0))

        val record = (result as MarkAttendanceResult.Marked).record
        assertEquals(now.toEpochMilli(), record.markedAtMillis)
        assertEquals(12.0, record.distanceMeters, 1e-6)
        assertEquals(8f, record.accuracyMeters)
        assertEquals(record, repository.stored.value)
    }

    @Test
    fun `out of range is rejected and nothing is saved`() = runTest {
        assertEquals(
            MarkAttendanceResult.Rejected(RejectionReason.OutOfRange),
            markAttendance(SampleOffice, fixAt(51.0)),
        )
        assertNull(repository.stored.value)
    }

    @Test
    fun `a fix less precise than the limit is rejected`() = runTest {
        assertEquals(
            MarkAttendanceResult.Rejected(RejectionReason.LowAccuracy),
            markAttendance(SampleOffice, fixAt(12.0, accuracy = 75f)),
        )
    }

    @Test
    fun `a fix older than the limit is rejected even if it was in range`() = runTest {
        elapsedRealtime = fixTakenAt + AttendancePolicy.MAX_FIX_AGE_MILLIS + 1

        assertEquals(
            MarkAttendanceResult.Rejected(RejectionReason.StaleLocation),
            markAttendance(SampleOffice, fixAt(12.0)),
        )
        assertNull(repository.stored.value)
    }

    @Test
    fun `storage failure is reported instead of thrown`() = runTest {
        repository.failSave = true

        assertEquals(MarkAttendanceResult.StorageFailed, markAttendance(SampleOffice, fixAt(12.0)))
    }
}
