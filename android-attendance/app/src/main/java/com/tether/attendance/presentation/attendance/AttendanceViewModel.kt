package com.tether.attendance.presentation.attendance

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.tether.attendance.TetherAttendanceApp
import com.tether.attendance.domain.model.AttendanceStatus
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.repository.AttendanceRepository
import com.tether.attendance.domain.repository.LocationRepository
import com.tether.attendance.domain.usecase.MarkAttendanceResult
import com.tether.attendance.domain.usecase.MarkAttendanceUseCase
import com.tether.attendance.domain.usecase.ObserveAttendanceStatusUseCase
import com.tether.attendance.domain.usecase.SetOfficeLocationResult
import com.tether.attendance.domain.usecase.SetOfficeLocationUseCase
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class AttendanceViewModel(
    observeAttendanceStatus: ObserveAttendanceStatusUseCase,
    attendanceRepository: AttendanceRepository,
    private val locationRepository: LocationRepository,
    private val setOfficeLocation: SetOfficeLocationUseCase,
    private val markAttendance: MarkAttendanceUseCase,
) : ViewModel() {

    /** Progress and errors of user actions; everything else is derived from storage and location. */
    private data class ActionState(
        val isSettingOffice: Boolean = false,
        val isMarkingAttendance: Boolean = false,
        val error: AttendanceError? = null,
    )

    private val actions = MutableStateFlow(ActionState())

    /** Incremented to restart location tracking, e.g. after permission is granted. */
    private val trackingRestarts = MutableStateFlow(0)

    @OptIn(ExperimentalCoroutinesApi::class)
    val uiState: StateFlow<AttendanceUiState> =
        combine(
            trackingRestarts.flatMapLatest { observeAttendanceStatus() },
            attendanceRepository.lastAttendance,
            actions,
        ) { status, lastAttendance, action ->
            AttendanceUiState(
                isOfficeLoaded = true,
                status = status,
                lastAttendance = lastAttendance,
                isSettingOffice = action.isSettingOffice,
                isMarkingAttendance = action.isMarkingAttendance,
                error = action.error,
            )
        }.stateIn(
            scope = viewModelScope,
            // Location updates run only while the screen is visible. The 5 s grace
            // period keeps them alive through a rotation instead of restarting GPS.
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = AttendanceUiState(),
        )

    private var setOfficeJob: Job? = null
    private var markAttendanceJob: Job? = null

    /** Call only once fine location permission is granted; the UI requests it first. */
    fun onSetOfficeLocation() {
        // A second tap while a fix is in progress must not start a parallel request.
        if (setOfficeJob?.isActive == true) return
        actions.update { it.copy(isSettingOffice = true, error = null) }
        setOfficeJob =
            viewModelScope.launch {
                // A successful save reaches the screen through the office flow,
                // which also restarts tracking against the new office.
                val error =
                    when (val result = setOfficeLocation()) {
                        is SetOfficeLocationResult.Saved -> null
                        is SetOfficeLocationResult.LocationFailed ->
                            result.error.toAttendanceError()
                        is SetOfficeLocationResult.LowAccuracy -> AttendanceError.OfficeLowAccuracy
                        SetOfficeLocationResult.StorageFailed -> AttendanceError.OfficeSaveFailed
                    }
                actions.update { it.copy(isSettingOffice = false, error = error) }
            }
    }

    fun onMarkAttendance() {
        if (markAttendanceJob?.isActive == true) return
        val measured = uiState.value.status as? AttendanceStatus.Measured ?: return
        actions.update { it.copy(isMarkingAttendance = true, error = null) }
        markAttendanceJob =
            viewModelScope.launch {
                // The use case re-checks the rules; the button state alone is not trusted.
                val error =
                    when (markAttendance(measured.office, measured.fix)) {
                        is MarkAttendanceResult.Marked -> null
                        is MarkAttendanceResult.Rejected -> AttendanceError.NoLongerEligible
                        MarkAttendanceResult.StorageFailed -> AttendanceError.AttendanceSaveFailed
                    }
                actions.update { it.copy(isMarkingAttendance = false, error = error) }
            }
    }

    /** Permission was granted from the tracking prompt; start measuring the distance. */
    fun onLocationPermissionGranted() {
        actions.update { it.copy(error = null) }
        restartTracking()
    }

    /** The permission dialog was answered without granting precise location. */
    fun onLocationPermissionDenied(coarseGranted: Boolean, canAskAgain: Boolean) {
        val error =
            when {
                coarseGranted -> AttendanceError.PreciseLocationDenied
                canAskAgain -> AttendanceError.PermissionDenied
                else -> AttendanceError.PermissionPermanentlyDenied
            }
        actions.update { it.copy(error = error) }
    }

    fun onErrorDismissed() {
        actions.update { it.copy(error = null) }
    }

    /**
     * The screen came back to the foreground, possibly from system settings.
     * Clears an error the user has since fixed there, and restarts tracking if
     * it was stopped by missing permission.
     */
    fun onScreenResumed() {
        actions.update { state ->
            val fixed =
                when (state.error) {
                    AttendanceError.PermissionDenied,
                    AttendanceError.PermissionPermanentlyDenied,
                    AttendanceError.PreciseLocationDenied,
                    -> locationRepository.hasLocationPermission()
                    AttendanceError.LocationDisabled -> locationRepository.isLocationEnabled()
                    else -> false
                }
            if (fixed) state.copy(error = null) else state
        }
        val status = uiState.value.status
        if (status is AttendanceStatus.LocationUnavailable &&
            status.error == LocationError.PermissionDenied &&
            locationRepository.hasLocationPermission()
        ) {
            restartTracking()
        }
    }

    private fun restartTracking() {
        trackingRestarts.update { it + 1 }
    }

    private fun LocationError.toAttendanceError() = when (this) {
        LocationError.PermissionDenied -> AttendanceError.PermissionDenied
        LocationError.LocationDisabled -> AttendanceError.LocationDisabled
        LocationError.Unavailable -> AttendanceError.LocationUnavailable
    }

    companion object {
        val Factory =
            viewModelFactory {
                initializer {
                    val container = (this[APPLICATION_KEY] as TetherAttendanceApp).container
                    AttendanceViewModel(
                        observeAttendanceStatus = container.observeAttendanceStatusUseCase(),
                        attendanceRepository = container.attendanceRepository,
                        locationRepository = container.locationRepository,
                        setOfficeLocation = container.setOfficeLocationUseCase(),
                        markAttendance = container.markAttendanceUseCase(),
                    )
                }
            }
    }
}
