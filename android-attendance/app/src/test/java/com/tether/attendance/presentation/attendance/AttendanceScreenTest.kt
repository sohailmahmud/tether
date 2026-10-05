package com.tether.attendance.presentation.attendance

import androidx.activity.ComponentActivity
import androidx.annotation.StringRes
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.tether.attendance.R
import com.tether.attendance.domain.model.AttendanceCheck
import com.tether.attendance.domain.model.AttendancePolicy
import com.tether.attendance.domain.model.AttendanceRecord
import com.tether.attendance.domain.model.AttendanceStatus
import com.tether.attendance.domain.model.Eligibility
import com.tether.attendance.domain.model.LocationError
import com.tether.attendance.presentation.theme.TetherTheme
import com.tether.attendance.testing.SampleOffice
import com.tether.attendance.testing.fixNorthOf
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * UI tests for [AttendanceScreen], run on the JVM through Robolectric. The
 * screen is stateless, so each test renders one [AttendanceUiState] and checks
 * what the user sees and which action a tap reports.
 *
 * The screen scrolls; a phone-width but extra-tall window keeps every section
 * on screen, so taps land on visible nodes as they would for a user.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h1400dp")
class AttendanceScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    /** Counts every callback, so a test can check exactly which one a tap fired. */
    private val calls = mutableMapOf<String, Int>()
    private val actions =
        AttendanceActions(
            onSetOfficeLocation = { record("setOffice") },
            onMarkAttendance = { record("mark") },
            onAllowLocation = { record("allowLocation") },
            onOpenAppSettings = { record("appSettings") },
            onOpenLocationSettings = { record("locationSettings") },
            onDismissError = { record("dismiss") },
        )

    private fun record(name: String) {
        calls[name] = (calls[name] ?: 0) + 1
    }

    private fun string(@StringRes id: Int, vararg args: Any): String =
        compose.activity.getString(id, *args)

    private fun show(state: AttendanceUiState) {
        compose.setContent { TetherTheme(darkTheme = false) { AttendanceScreen(state, actions) } }
    }

    private fun loaded(
        status: AttendanceStatus,
        lastAttendance: AttendanceRecord? = null,
        isSettingOffice: Boolean = false,
        error: AttendanceError? = null,
    ) = AttendanceUiState(
        isOfficeLoaded = true,
        status = status,
        lastAttendance = lastAttendance,
        isSettingOffice = isSettingOffice,
        error = error,
    )

    private fun measured(meters: Double, eligibility: Eligibility, accuracy: Float? = 8f) =
        AttendanceStatus.Measured(
            office = SampleOffice,
            fix = fixNorthOf(SampleOffice, meters, accuracy),
            check = AttendanceCheck(distanceMeters = meters, eligibility = eligibility),
        )

    private fun markButton() = compose.onNodeWithText(string(R.string.mark_attendance))

    private fun setOfficeButton() = compose.onNodeWithText(string(R.string.set_office_location))

    @Test
    fun `with no office set, check-in is locked and setting the office needs no confirmation`() {
        show(loaded(AttendanceStatus.OfficeNotSet))

        compose.onNodeWithText(string(R.string.office_not_set_chip)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.range_hint_office_not_set)).assertIsDisplayed()
        markButton().assertIsNotEnabled()

        setOfficeButton().performClick()

        assertEquals(1, calls["setOffice"])
        compose.onNodeWithText(string(R.string.replace_office_title)).assertDoesNotExist()
    }

    @Test
    fun `out of range shows the distance and the 50 m rule, and check-in stays locked`() {
        show(loaded(measured(120.0, Eligibility.OutOfRange)))

        compose
            .onNodeWithText(
                string(
                    R.string.range_hint_out_of_range,
                    formatDistance(120.0),
                    AttendancePolicy.RADIUS_METERS,
                ),
            ).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.range_out_of_range).uppercase()).assertIsDisplayed()
        markButton().assertIsNotEnabled()
    }

    @Test
    fun `in range enables Mark Attendance and reports the tap`() {
        show(loaded(measured(20.0, Eligibility.Eligible)))

        compose
            .onNodeWithText(string(R.string.range_hint_in_range, formatDistance(20.0)))
            .assertIsDisplayed()
        markButton().assertIsEnabled().performClick()

        assertEquals(1, calls["mark"])
    }

    @Test
    fun `a fix too imprecise to trust keeps check-in locked and says why`() {
        show(loaded(measured(20.0, Eligibility.LowAccuracy, accuracy = 70f)))

        compose
            .onNodeWithText(
                string(
                    R.string.range_hint_weak_signal,
                    70,
                    AttendancePolicy.MAX_ACCURACY_METERS.toInt(),
                ),
            ).assertIsDisplayed()
        markButton().assertIsNotEnabled()
    }

    @Test
    fun `replacing an existing office asks for confirmation first`() {
        show(loaded(measured(20.0, Eligibility.Eligible)))

        setOfficeButton().performClick()
        compose.onNodeWithText(string(R.string.replace_office_title)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.cancel)).performClick()
        assertEquals(null, calls["setOffice"])

        setOfficeButton().performClick()
        compose.onNodeWithText(string(R.string.replace_office_confirm)).performClick()
        assertEquals(1, calls["setOffice"])
    }

    @Test
    fun `while the office fix is being taken, its button shows progress and is disabled`() {
        show(loaded(AttendanceStatus.OfficeNotSet, isSettingOffice = true))

        compose.onNodeWithText(string(R.string.setting_office_location)).assertIsNotEnabled()
    }

    @Test
    fun `missing permission offers to allow location`() {
        show(
            loaded(
                AttendanceStatus.LocationUnavailable(SampleOffice, LocationError.PermissionDenied),
            ),
        )

        compose.onNodeWithText(string(R.string.range_hint_permission_needed)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.action_allow_location)).performClick()

        assertEquals(1, calls["allowLocation"])
        markButton().assertIsNotEnabled()
    }

    @Test
    fun `location services off offers to open location settings`() {
        show(
            loaded(
                AttendanceStatus.LocationUnavailable(SampleOffice, LocationError.LocationDisabled),
            ),
        )

        compose.onNodeWithText(string(R.string.action_turn_on_location_long)).performClick()

        assertEquals(1, calls["locationSettings"])
    }

    @Test
    fun `no fix for a while explains the lost signal`() {
        show(loaded(AttendanceStatus.LocationUnavailable(SampleOffice, LocationError.Unavailable)))

        compose.onNodeWithText(string(R.string.range_hint_no_signal)).assertIsDisplayed()
        markButton().assertIsNotEnabled()
    }

    @Test
    fun `an error banner offers its fix and can be dismissed`() {
        show(
            loaded(
                AttendanceStatus.OfficeNotSet,
                error = AttendanceError.PermissionPermanentlyDenied,
            ),
        )

        compose.onNodeWithText(
            string(R.string.error_permission_permanently_denied),
        ).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.action_open_settings)).performClick()
        compose.onNodeWithText(string(R.string.action_dismiss)).performClick()

        assertEquals(1, calls["appSettings"])
        assertEquals(1, calls["dismiss"])
    }

    @Test
    fun `an office fix that was too imprecise is explained in the banner`() {
        show(loaded(AttendanceStatus.OfficeNotSet, error = AttendanceError.OfficeLowAccuracy))

        compose.onNodeWithText(string(R.string.error_office_low_accuracy)).assertIsDisplayed()
    }

    @Test
    fun `the last check-in is shown under the button`() {
        val record =
            AttendanceRecord(
                markedAtMillis = System.currentTimeMillis(),
                distanceMeters = 12.0,
                accuracyMeters = 5f,
            )
        show(loaded(measured(6.0, Eligibility.Eligible), lastAttendance = record))

        compose
            .onNodeWithText("${formatDistance(12.0)} from the office", substring = true)
            .assertIsDisplayed()
    }
}
