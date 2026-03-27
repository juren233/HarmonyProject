package com.harmony.pet.pet_care_harmony

private const val preferredRefreshRateHz = 120f
private const val refreshRateToleranceHz = 0.5f

object RefreshRatePreferences {
    fun preferredRefreshRateHz(
        supportedRefreshRates: List<Float>,
        preferredRefreshRate: Float = preferredRefreshRateHz,
    ): Float {
        if (supportedRefreshRates.isEmpty()) {
            return preferredRefreshRate
        }

        val distinctRates = supportedRefreshRates
            .filter { it > 0f }
            .distinct()
            .sortedDescending()

        if (distinctRates.isEmpty()) {
            return preferredRefreshRate
        }

        return distinctRates.firstOrNull {
            kotlin.math.abs(it - preferredRefreshRate) <= refreshRateToleranceHz
        } ?: distinctRates.first()
    }
}
