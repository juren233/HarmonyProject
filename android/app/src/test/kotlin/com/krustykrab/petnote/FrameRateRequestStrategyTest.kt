package com.krustykrab.petnote

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FrameRateRequestStrategyTest {
    @Test
    fun `surface frame rate requests require api 30 and a positive refresh rate`() {
        assertFalse(
            FrameRateRequestStrategy.shouldApplySurfaceFrameRate(
                sdkInt = 29,
                requestedRefreshRate = 120f,
            ),
        )

        assertFalse(
            FrameRateRequestStrategy.shouldApplySurfaceFrameRate(
                sdkInt = 30,
                requestedRefreshRate = 0f,
            ),
        )

        assertTrue(
            FrameRateRequestStrategy.shouldApplySurfaceFrameRate(
                sdkInt = 30,
                requestedRefreshRate = 120f,
            ),
        )
    }
}
