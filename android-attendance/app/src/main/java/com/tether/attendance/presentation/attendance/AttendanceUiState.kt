package com.tether.attendance.presentation.attendance

import com.tether.attendance.domain.model.OfficeLocation

/** Everything [AttendanceScreen] renders. The screen holds no other state of its own. */
data class AttendanceUiState(
    /** False until storage has been read once, so "no office set" never flashes on launch. */
    val isOfficeLoaded: Boolean = false,
    val officeLocation: OfficeLocation? = null,
    /** True while a fix is being taken for Set Office Location. */
    val isSettingOffice: Boolean = false,
    val error: AttendanceError? = null,
)

/** Problems the user can see and, where possible, fix. */
enum class AttendanceError {
    /** Location was denied; asking again will show the system dialog. */
    PermissionDenied,

    /** Location was denied with "don't ask again"; only system settings can grant it now. */
    PermissionPermanentlyDenied,

    /** Only approximate location was granted, which is too coarse for a 50 m check. */
    PreciseLocationDenied,

    LocationDisabled,
    LocationUnavailable,
    SaveFailed,
}
