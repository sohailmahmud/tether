package com.tether.attendance.domain

import com.tether.attendance.domain.model.AttendancePolicy
import com.tether.attendance.domain.model.Eligibility
import com.tether.attendance.testing.SampleOffice
import com.tether.attendance.testing.fixNorthOf
import org.junit.Assert.assertEquals
import org.junit.Test

class AttendancePolicyTest {
    private fun eligibilityAt(meters: Double, accuracy: Float? = 8f) = AttendancePolicy.evaluate(
        SampleOffice,
        fixNorthOf(SampleOffice, meters, accuracy),
    ).eligibility

    @Test
    fun `inside the radius with a good fix is eligible`() {
        assertEquals(Eligibility.Eligible, eligibilityAt(12.0))
    }

    @Test
    fun `the 50 m boundary is inclusive`() {
        assertEquals(Eligibility.Eligible, eligibilityAt(49.99))
        assertEquals(Eligibility.OutOfRange, eligibilityAt(50.01))
    }

    @Test
    fun `outside the radius is out of range`() {
        assertEquals(Eligibility.OutOfRange, eligibilityAt(120.0))
    }

    @Test
    fun `reports the measured distance`() {
        assertEquals(
            120.0,
            AttendancePolicy.evaluate(SampleOffice, fixNorthOf(SampleOffice, 120.0)).distanceMeters,
            1e-6,
        )
    }

    @Test
    fun `inside the radius but with a fix worse than 50 m is not trusted`() {
        assertEquals(Eligibility.LowAccuracy, eligibilityAt(20.0, accuracy = 72f))
        assertEquals(Eligibility.LowAccuracy, eligibilityAt(20.0, accuracy = null))
    }

    @Test
    fun `accuracy exactly at the limit is accepted`() {
        assertEquals(
            Eligibility.Eligible,
            eligibilityAt(20.0, accuracy = AttendancePolicy.MAX_ACCURACY_METERS),
        )
    }

    @Test
    fun `clearly outside is reported as out of range even on a poor fix`() {
        assertEquals(Eligibility.OutOfRange, eligibilityAt(300.0, accuracy = 90f))
    }
}
