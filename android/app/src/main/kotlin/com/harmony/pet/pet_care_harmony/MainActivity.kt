package com.harmony.pet.pet_care_harmony

import android.os.Build
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        requestHighRefreshRate()
    }

    private fun requestHighRefreshRate() {
        val requestedRefreshRate = RefreshRatePreferences.preferredRefreshRateHz(
            supportedRefreshRates = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                display?.supportedModes?.map { it.refreshRate }.orEmpty()
            } else {
                emptyList()
            },
        )

        window.attributes = window.attributes.apply {
            preferredRefreshRate = requestedRefreshRate
        }

        if (FrameRateRequestStrategy.shouldApplySurfaceFrameRate(
                sdkInt = Build.VERSION.SDK_INT,
                requestedRefreshRate = requestedRefreshRate,
            )
        ) {
            findSurfaceView(window.decorView)?.holder?.surface?.let { surface ->
                if (surface.isValid) {
                    surface.setFrameRate(
                        requestedRefreshRate,
                        Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    )
                }
            }
        }
    }

    private fun findSurfaceView(view: View): SurfaceView? {
        return when (view) {
            is SurfaceView -> view
            is ViewGroup -> {
                for (index in 0 until view.childCount) {
                    findSurfaceView(view.getChildAt(index))?.let { return it }
                }
                null
            }
            else -> null
        }
    }
}
