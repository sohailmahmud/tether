package com.tether.attendance.domain.usecase

import com.tether.attendance.domain.model.AttendancePolicy
import com.tether.attendance.domain.model.AttendanceRecord
import com.tether.attendance.domain.model.Eligibility
import com.tether.attendance.domain.model.LocationData
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.domain.repository.AttendanceRepository
import java.io.IOException
import java.time.Clock

/**
 * Records a check-in after re-checking the rules against [fix]. The button's
 * enabled state is not trusted on its own: the user may have moved, or updates
 * may have stopped, between the screen rendering and the tap.
 */
class MarkAttendanceUseCase(
    private val attendanceRepository: AttendanceRepository,
    private val clock: Clock,
    /** Monotonic time since boot, in milliseconds (SystemClock.elapsedRealtime in production). */
    private val elapsedRealtimeMillis: () -> Long,
) {
    suspend operator fun invoke(office: OfficeLocation, fix: LocationData): MarkAttendanceResult {
        val fixAge = elapsedRealtimeMillis() - fix.elapsedRealtimeMillis
        if (fixAge > AttendancePolicy.MAX_FIX_AGE_MILLIS) {
            return MarkAttendanceResult.Rejected(RejectionReason.StaleLocation)
        }
        val check = AttendancePolicy.evaluate(office, fix)
        when (check.eligibility) {
            Eligibility.Eligible -> Unit
            Eligibility.OutOfRange -> return MarkAttendanceResult.Rejected(
                RejectionReason.OutOfRange,
            )
            Eligibility.LowAccuracy -> return MarkAttendanceResult.Rejected(
                RejectionReason.LowAccuracy,
            )
        }
        val record =
            AttendanceRecord(
                markedAtMillis = clock.millis(),
                distanceMeters = check.distanceMeters,
                accuracyMeters = fix.accuracyMeters,
            )
        return try {
            attendanceRepository.save(record)
            MarkAttendanceResult.Marked(record)
        } catch (e: IOException) {
            MarkAttendanceResult.StorageFailed
        }
    }
}

sealed interface MarkAttendanceResult {
    data class Marked(val record: AttendanceRecord) : MarkAttendanceResult

    data class Rejected(val reason: RejectionReason) : MarkAttendanceResult

    data object StorageFailed : MarkAttendanceResult
}

enum class RejectionReason { OutOfRange, LowAccuracy, StaleLocation }
