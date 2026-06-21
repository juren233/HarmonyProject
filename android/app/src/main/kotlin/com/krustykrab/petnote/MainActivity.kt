package com.krustykrab.petnote

import android.graphics.Color
import android.os.Build
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    private var notificationBridge: PetNoteNotificationBridge? = null
    private var aiSecretStoreBridge: PetNoteAiSecretStoreBridge? = null
    private var dataPackageFileAccessBridge: PetNoteDataPackageFileAccessBridge? = null
    private var appDirectoryBridge: PetNoteAppDirectoryBridge? = null
    private var introHapticsBridge: PetNoteIntroHapticsBridge? = null
    private var interactionHapticsBridge: PetNoteInteractionHapticsBridge? = null
    private var nativeOptionPickerBridge: PetNoteNativeOptionPickerBridge? = null
    private var nativePetPhotoPickerBridge: PetNoteNativePetPhotoPickerBridge? = null
    private var keepAliveBridge: PetNoteKeepAliveBridge? = null
    private var rtcBridge: PetNoteRtcBridge? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        applyImmersiveSystemBars()
        requestHighRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        rtcBridge = PetNoteRtcBridge(
            activity = this,
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "petnote/android_liquid_glass_dock",
                AndroidLiquidGlassDockFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "petnote/android_liquid_glass_toggle",
                AndroidLiquidGlassToggleFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "petnote/rtc_video_view",
                PetNoteRtcVideoViewFactory(rtcBridge!!),
            )
        notificationBridge = PetNoteNotificationBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        aiSecretStoreBridge = PetNoteAiSecretStoreBridge(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        dataPackageFileAccessBridge = PetNoteDataPackageFileAccessBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        appDirectoryBridge = PetNoteAppDirectoryBridge(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        introHapticsBridge = PetNoteIntroHapticsBridge(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        interactionHapticsBridge = PetNoteInteractionHapticsBridge(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        nativeOptionPickerBridge = PetNoteNativeOptionPickerBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        nativePetPhotoPickerBridge = PetNoteNativePetPhotoPickerBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        keepAliveBridge = PetNoteKeepAliveBridge(
            activity = this,
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onResume() {
        super.onResume()
        applyImmersiveSystemBars()
        requestHighRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyImmersiveSystemBars()
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        notificationBridge?.handleIntent(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (notificationBridge?.handlePermissionResult(requestCode, grantResults) == true) {
            return
        }
        if (rtcBridge?.handlePermissionResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: android.content.Intent?,
    ) {
        if (dataPackageFileAccessBridge?.handleActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        dataPackageFileAccessBridge?.close()
        dataPackageFileAccessBridge = null
        appDirectoryBridge?.close()
        appDirectoryBridge = null
        keepAliveBridge?.close()
        keepAliveBridge = null
        rtcBridge?.close()
        rtcBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
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

    private fun applyImmersiveSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.navigationBarDividerColor = Color.TRANSPARENT
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
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
