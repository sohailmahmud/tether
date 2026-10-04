package com.tether.attendance.presentation.attendance

import com.tether.attendance.domain.model.AttendanceRecord
import com.tether.attendance.domain.model.AttendanceStatus
import com.tether.attendance.domain.model.Eligibility
import com.tether.attendance.domain.model.LocationData
import com.tether.attendance.domain.model.OfficeLocation

/** Everything [AttendanceScreen] renders. The screen holds no other state of its own. */
data class AttendanceUiState(
    /** False until storage has been read once, so "no office set" never flashes on launch. */
    val isOfficeLoaded: Boolean = false,
    val status: AttendanceStatus = AttendanceStatus.OfficeNotSet,
    val lastAttendance: AttendanceRecord? = null,
    /** True while a fix is being taken for Set Office Location. */
    val isSettingOffice: Boolean = false,
    val isMarkingAttendance: Boolean = false,
    val error: AttendanceError? = null,
) {
    val officeLocation: OfficeLocation? get() = status.office

    private val measured: AttendanceStatus.Measured? get() = status as? AttendanceStatus.Measured

    val currentLocation: LocationData? get() = measured?.fix

    val distanceMeters: Double? get() = measured?.check?.distanceMeters

    val isWithinRadius: Boolean get() = measured?.check?.eligibility == Eligibility.Eligible

    val canMarkAttendance: Boolean get() = isWithinRadius && !isMarkingAttendance
}

/** Problems from a user action, shown in a banner until dismissed or fixed. */
enum class AttendanceError {
    /** Location was denied; asking again will show the system dialog. */
    PermissionDenied,

    /** Location was denied with "don't ask again"; only system settings can grant it now. */
    PermissionPermanentlyDenied,

    /** Only approximate location was granted, which is too coarse for a 50 m check. */
    PreciseLocationDenied,

    LocationDisabled,
    LocationUnavailable,
    OfficeSaveFailed,

    /** Between the screen rendering and the tap, the user moved or the fix went stale. */
    NoLongerEligible,

    AttendanceSaveFailed,
}
