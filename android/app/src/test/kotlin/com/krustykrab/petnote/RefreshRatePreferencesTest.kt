package com.krustykrab.petnote

import org.junit.Assert.assertEquals
import org.junit.Test

class RefreshRatePreferencesTest {
    @Test
    fun `prefers 120hz when supported`() {
        val requested = RefreshRatePreferences.preferredRefreshRateHz(
            supportedRefreshRates = listOf(60f, 90f, 120f),
        )

        assertEquals(120f, requested, 0.01f)
    }

    @Test
    fun `falls back to highest supported refresh rate when 120hz is unavailable`() {
        val requested = RefreshRatePreferences.preferredRefreshRateHz(
            supportedRefreshRates = listOf(60f, 90f),
        )

        assertEquals(90f, requested, 0.01f)
    }

    @Test
    fun `uses preferred refresh rate when supported list is unavailable`() {
        val requested = RefreshRatePreferences.preferredRefreshRateHz(
            supportedRefreshRates = emptyList(),
        )

        assertEquals(120f, requested, 0.01f)
    }
}
