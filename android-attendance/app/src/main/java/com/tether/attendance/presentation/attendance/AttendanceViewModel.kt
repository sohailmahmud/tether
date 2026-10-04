package com.tether.attendance.presentation.attendance

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.tether.attendance.TetherAttendanceApp
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.domain.repository.LocationRepository
import com.tether.attendance.domain.repository.OfficeLocationRepository
import com.tether.attendance.domain.usecase.SetOfficeLocationResult
import com.tether.attendance.domain.usecase.SetOfficeLocationUseCase
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class AttendanceViewModel(
    officeLocationRepository: OfficeLocationRepository,
    private val locationRepository: LocationRepository,
    private val setOfficeLocation: SetOfficeLocationUseCase,
) : ViewModel() {

    private val _uiState = MutableStateFlow(AttendanceUiState())
    val uiState: StateFlow<AttendanceUiState> = _uiState.asStateFlow()

    private var setOfficeJob: Job? = null

    init {
        // Storage is the single source of truth: a successful save reaches the
        // screen through this flow, not by copying the result into state.
        viewModelScope.launch {
            officeLocationRepository.officeLocation.collect { office ->
                _uiState.update { it.copy(isOfficeLoaded = true, officeLocation = office) }
            }
        }
    }

    /** Call only once fine location permission is granted; the UI requests it first. */
    fun onSetOfficeLocation() {
        // A second tap while a fix is in progress must not start a parallel request.
        if (setOfficeJob?.isActive == true) return
        _uiState.update { it.copy(isSettingOffice = true, error = null) }
        setOfficeJob =
            viewModelScope.launch {
                val error =
                    when (val result = setOfficeLocation()) {
                        is SetOfficeLocationResult.Saved -> null
                        is SetOfficeLocationResult.LocationFailed ->
                            result.error.toAttendanceError()
                        SetOfficeLocationResult.StorageFailed -> AttendanceError.SaveFailed
                    }
                _uiState.update { it.copy(isSettingOffice = false, error = error) }
            }
    }

    /** The permission dialog was answered without granting precise location. */
    fun onLocationPermissionDenied(coarseGranted: Boolean, canAskAgain: Boolean) {
        val error =
            when {
                coarseGranted -> AttendanceError.PreciseLocationDenied
                canAskAgain -> AttendanceError.PermissionDenied
                else -> AttendanceError.PermissionPermanentlyDenied
            }
        _uiState.update { it.copy(error = error) }
    }

    fun onErrorDismissed() {
        _uiState.update { it.copy(error = null) }
    }

    /**
     * The screen came back to the foreground, possibly from system settings.
     * Clears an error the user has since fixed there, so it doesn't linger.
     */
    fun onScreenResumed() {
        _uiState.update { state ->
            val fixed =
                when (state.error) {
                    AttendanceError.PermissionDenied,
                    AttendanceError.PermissionPermanentlyDenied,
                    AttendanceError.PreciseLocationDenied,
                    -> locationRepository.hasLocationPermission()
                    AttendanceError.LocationDisabled -> locationRepository.isLocationEnabled()
                    AttendanceError.LocationUnavailable, AttendanceError.SaveFailed, null -> false
                }
            if (fixed) state.copy(error = null) else state
        }
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
                        officeLocationRepository = container.officeLocationRepository,
                        locationRepository = container.locationRepository,
                        setOfficeLocation = container.setOfficeLocationUseCase(),
                    )
                }
            }
    }
}
