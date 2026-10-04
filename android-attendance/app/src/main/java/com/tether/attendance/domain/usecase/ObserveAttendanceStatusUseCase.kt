package com.tether.attendance.domain.usecase

import com.tether.attendance.domain.model.AttendancePolicy
import com.tether.attendance.domain.model.AttendanceStatus
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.model.LocationResult
import com.tether.attendance.domain.model.OfficeLocation
import com.tether.attendance.domain.repository.LocationRepository
import com.tether.attendance.domain.repository.OfficeLocationRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.transformLatest

/**
 * Combines the saved office with live location into an [AttendanceStatus].
 *
 * Location is only tracked while an office is set, and tracking restarts when
 * the office changes, so every fix is measured against the current office.
 * A fix stops counting once it is older than [AttendancePolicy.MAX_FIX_AGE_MILLIS].
 */
class ObserveAttendanceStatusUseCase(
    private val officeLocationRepository: OfficeLocationRepository,
    private val locationRepository: LocationRepository,
) {
    @OptIn(ExperimentalCoroutinesApi::class)
    operator fun invoke(): Flow<AttendanceStatus> =
        officeLocationRepository.officeLocation.flatMapLatest { office ->
            if (office == null) flowOf(AttendanceStatus.OfficeNotSet) else trackAgainst(office)
        }

    @OptIn(ExperimentalCoroutinesApi::class)
    private fun trackAgainst(office: OfficeLocation): Flow<AttendanceStatus> =
        locationRepository.locationUpdates()
            // null marks "tracking started, no result yet".
            .onStart<LocationResult?> { emit(null) }
            // transformLatest cancels the pending timeout as soon as a newer result arrives.
            .transformLatest { result ->
                when (result) {
                    null -> emit(AttendanceStatus.Locating(office))
                    is LocationResult.Success ->
                        emit(
                            AttendanceStatus.Measured(
                                office = office,
                                fix = result.location,
                                check = AttendancePolicy.evaluate(office, result.location),
                            ),
                        )
                    is LocationResult.Failure -> {
                        emit(AttendanceStatus.LocationUnavailable(office, result.error))
                        return@transformLatest
                    }
                }
                // No newer fix in time: the last one (or the wait for a first one) has gone stale.
                delay(AttendancePolicy.MAX_FIX_AGE_MILLIS)
                emit(AttendanceStatus.LocationUnavailable(office, LocationError.Unavailable))
            }
}
