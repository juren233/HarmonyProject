package com.krustykrab.petnote

import android.os.Build
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity(), ViewModelStoreOwner, SavedStateRegistryOwner {
    private val _viewModelStore = ViewModelStore()
    private val _savedStateRegistryController = SavedStateRegistryController.create(this)

    override val viewModelStore: ViewModelStore
        get() = _viewModelStore

    override val savedStateRegistry: SavedStateRegistry
        get() = _savedStateRegistryController.savedStateRegistry

    private var notificationBridge: PetNoteNotificationBridge? = null
    private var aiSecretStoreBridge: PetNoteAiSecretStoreBridge? = null
    private var dataPackageFileAccessBridge: PetNoteDataPackageFileAccessBridge? = null
    private var nativeOptionPickerBridge: PetNoteNativeOptionPickerBridge? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        _savedStateRegistryController.performRestore(savedInstanceState)
        super.onCreate(savedInstanceState)
        
        val decorView = window.decorView
        decorView.setViewTreeLifecycleOwner(this)
        decorView.setViewTreeViewModelStoreOwner(this)
        decorView.setViewTreeSavedStateRegistryOwner(this)
        
        requestHighRefreshRate()
    }

    override fun onSaveInstanceState(outState: android.os.Bundle) {
        super.onSaveInstanceState(outState)
        _savedStateRegistryController.performSave(outState)
    }

    override fun onDestroy() {
        super.onDestroy()
        _viewModelStore.clear()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "petnote/android_liquid_glass_dock",
                AndroidLiquidGlassDockFactory(flutterEngine.dartExecutor.binaryMessenger),
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
        nativeOptionPickerBridge = PetNoteNativeOptionPickerBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onResume() {
        super.onResume()
        requestHighRefreshRate()
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
