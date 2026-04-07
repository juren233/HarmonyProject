package com.krustykrab.petnote

import android.os.Build

object FrameRateRequestStrategy {
    fun shouldApplySurfaceFrameRate(
        sdkInt: Int,
        requestedRefreshRate: Float,
    ): Boolean {
        return sdkInt >= Build.VERSION_CODES.R && requestedRefreshRate > 0f
    }
}
