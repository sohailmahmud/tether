package com.tether.attendance.domain

import com.tether.attendance.domain.model.GeoDistance
import com.tether.attendance.testing.METERS_PER_DEGREE_LATITUDE
import org.junit.Assert.assertEquals
import org.junit.Test

class GeoDistanceTest {
    @Test
    fun `same point is zero metres apart`() {
        assertEquals(0.0, GeoDistance.meters(23.78, 90.40, 23.78, 90.40), 0.0)
    }

    @Test
    fun `one degree of latitude is about 111 km`() {
        assertEquals(METERS_PER_DEGREE_LATITUDE, GeoDistance.meters(0.0, 0.0, 1.0, 0.0), 0.001)
        assertEquals(111_195.0, METERS_PER_DEGREE_LATITUDE, 1.0)
    }

    @Test
    fun `a 50 m offset in latitude measures 50 m`() {
        val dLat = 50 / METERS_PER_DEGREE_LATITUDE
        assertEquals(50.0, GeoDistance.meters(23.78, 90.40, 23.78 + dLat, 90.40), 1e-6)
    }

    @Test
    fun `longitude distance shrinks with latitude`() {
        // At 60 degrees a degree of longitude is half as long as at the equator.
        val atEquator = GeoDistance.meters(0.0, 0.0, 0.0, 0.001)
        val at60 = GeoDistance.meters(60.0, 0.0, 60.0, 0.001)
        assertEquals(atEquator / 2, at60, 0.01)
    }

    @Test
    fun `distance is symmetric`() {
        assertEquals(
            GeoDistance.meters(23.78, 90.40, 23.79, 90.41),
            GeoDistance.meters(23.79, 90.41, 23.78, 90.40),
            1e-9,
        )
    }

    @Test
    fun `antipodal points do not produce NaN`() {
        assertEquals(Math.PI * 6_371_008.8, GeoDistance.meters(0.0, 0.0, 0.0, 180.0), 1.0)
    }
}
