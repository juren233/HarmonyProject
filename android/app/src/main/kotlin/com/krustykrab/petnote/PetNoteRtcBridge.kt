package com.krustykrab.petnote

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.alivc.rtc.AliRtcAuthInfo
import com.alivc.rtc.AliRtcEngine
import com.alivc.rtc.AliRtcEngine.AliRtcMuteLocalAudioMode
import com.alivc.rtc.AliRtcEngine.AliRtcRenderMode
import com.alivc.rtc.AliRtcEngine.AliRtcVideoDimensions
import com.alivc.rtc.AliRtcEngine.AliRtcVideoEncoderBitrate
import com.alivc.rtc.AliRtcEngine.AliRtcVideoCanvas
import com.alivc.rtc.AliRtcEngine.AliRtcVideoEncoderConfiguration
import com.alivc.rtc.AliRtcEngine.AliRtcVideoTrack
import com.alivc.rtc.AliRtcEngine.AliRtcAudioTrack
import com.alivc.rtc.AliRtcEngine.AliRTCSdkChannelProfile
import com.alivc.rtc.AliRtcEngine.AliRTCSdkClientRole
import com.alivc.rtc.AliRtcEngineImpl
import com.alivc.rtc.AliRtcEngineNotify
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PetNoteRtcBridge(
    private val activity: Activity,
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var engine: AliRtcEngine? = null
    private var remoteUserId: String? = null
    private var localContainer: FrameLayout? = null
    private var remoteContainer: FrameLayout? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val rtcNotify = object : AliRtcEngineNotify() {
        override fun onRemoteUserOnLineNotify(uid: String, elapsed: Int) {
            handleRemoteMediaAvailable(uid)
        }

        override fun onRemoteTrackAvailableNotify(
            uid: String,
            audioTrack: AliRtcAudioTrack,
            videoTrack: AliRtcVideoTrack,
        ) {
            handleRemoteMediaAvailable(uid)
        }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    ensureEngine()
                    result.success(null)
                }
                "getMediaPermissionState" -> {
                    result.success(mediaPermissionState())
                }
                "requestMediaPermission" -> {
                    requestMediaPermission(result)
                }
                "openMediaPermissionSettings" -> {
                    result.success(openMediaPermissionSettings())
                }
                "join" -> {
                    join(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                    result.success(null)
                }
                "leave" -> {
                    engine?.leaveChannel()
                    result.success(null)
                }
                "toggleCamera" -> {
                    val enabled = (call.argument<Boolean>("enabled") ?: true)
                    engine?.muteLocalCamera(!enabled, AliRtcVideoTrack.AliRtcVideoTrackCamera)
                    result.success(null)
                }
                "toggleMicrophone" -> {
                    val enabled = (call.argument<Boolean>("enabled") ?: true)
                    engine?.muteLocalMic(!enabled, AliRtcMuteLocalAudioMode.AliRtcMuteOnlyMicAudioMode)
                    result.success(null)
                }
                "toggleSpeaker" -> {
                    val enabled = (call.argument<Boolean>("enabled") ?: true)
                    engine?.enableSpeakerphone(enabled)
                    result.success(null)
                }
                "switchCamera" -> {
                    engine?.switchCamera()
                    result.success(null)
                }
                "dispose" -> {
                    releaseEngine()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("rtc_native_error", error.message, null)
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pendingPermissionResult?.success(permissionRequestResult(mediaPermissionState(), false))
        pendingPermissionResult = null
        releaseEngine()
    }

    fun handlePermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != MEDIA_PERMISSION_REQUEST_CODE) {
            return false
        }
        val pendingResult = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingResult.success(
            permissionRequestResult(if (granted) "authorized" else mediaPermissionState(), true),
        )
        return true
    }

    private fun ensureEngine(): AliRtcEngine {
        val existing = engine
        if (existing != null) {
            return existing
        }
        val created = AliRtcEngineImpl.getInstance(context)
        created.setRtcEngineNotify(rtcNotify)
        engine = created
        return created
    }

    private fun mediaPermissionState(): String {
        return if (mediaPermissions.all { permission ->
                ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
            }
        ) {
            "authorized"
        } else {
            "denied"
        }
    }

    private fun requestMediaPermission(result: MethodChannel.Result) {
        if (mediaPermissionState() == "authorized") {
            result.success(permissionRequestResult("authorized", false))
            return
        }
        val previousResult = pendingPermissionResult
        if (previousResult != null) {
            previousResult.success(permissionRequestResult(mediaPermissionState(), false))
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            mediaPermissions,
            MEDIA_PERMISSION_REQUEST_CODE,
        )
    }

    private fun openMediaPermissionSettings(): String {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            "opened"
        } catch (_: Throwable) {
            "failed"
        }
    }

    private fun permissionRequestResult(state: String, promptHandled: Boolean): Map<String, Any> {
        return mapOf(
            "state" to state,
            "promptHandled" to promptHandled,
        )
    }

    private fun join(arguments: Map<*, *>) {
        val rtcEngine = ensureEngine()
        configureVideoEncoder(rtcEngine, arguments)
        remoteUserId = requireString(arguments, "remoteUserId")
        rtcEngine.setChannelProfile(AliRTCSdkChannelProfile.AliRTCSdkInteractiveLive)
        rtcEngine.setClientRole(AliRTCSdkClientRole.AliRTCSdkInteractive)
        rtcEngine.setDefaultSubscribeAllRemoteAudioStreams(true)
        rtcEngine.setDefaultSubscribeAllRemoteVideoStreams(true)
        attachLocalView(rtcEngine)
        attachRemoteView(rtcEngine)
        val authInfo = AliRtcAuthInfo()
        authInfo.appId = requireString(arguments, "appId")
        authInfo.channelId = requireString(arguments, "channelId")
        authInfo.userId = requireString(arguments, "userId")
        authInfo.token = requireString(arguments, "token")
        authInfo.nonce = requireString(arguments, "nonce")
        authInfo.timestamp = requireLong(arguments, "timestamp")
        rtcEngine.joinChannel(authInfo, null)
        rtcEngine.publishLocalAudioStream(true)
        rtcEngine.publishLocalVideoStream(true)
        rtcEngine.subscribeAllRemoteAudioStreams(true)
        rtcEngine.subscribeAllRemoteVideoStreams(true)
        remoteUserId?.let { userId -> subscribeRemoteMedia(rtcEngine, userId) }
    }

    private fun configureVideoEncoder(rtcEngine: AliRtcEngine, arguments: Map<*, *>) {
        val width = requireInt(arguments, "videoWidth")
        val height = requireInt(arguments, "videoHeight")
        require(width == 1280 && height == 720) { "rtc video quality must be 720P" }
        val config = AliRtcVideoEncoderConfiguration()
        config.dimensions = AliRtcVideoDimensions(width, height)
        config.bitrate = AliRtcVideoEncoderBitrate.AliRtcVideoEncoderStandardBitrate.getValue()
        rtcEngine.setVideoEncoderConfiguration(config)
    }

    private fun releaseEngine() {
        engine?.stopPreview()
        engine?.setLocalViewConfig(null as AliRtcVideoCanvas?, AliRtcVideoTrack.AliRtcVideoTrackCamera)
        remoteUserId?.let { userId ->
            engine?.setRemoteViewConfig(null as AliRtcVideoCanvas?, userId, AliRtcVideoTrack.AliRtcVideoTrackCamera)
        }
        engine?.leaveChannel()
        engine?.destroy()
        engine = null
        remoteUserId = null
    }

    private fun handleRemoteMediaAvailable(uid: String) {
        if (uid != remoteUserId) {
            return
        }
        activity.runOnUiThread {
            val rtcEngine = engine ?: return@runOnUiThread
            subscribeRemoteMedia(rtcEngine, uid)
            attachRemoteView(rtcEngine)
        }
    }

    fun bindVideoView(role: String, remoteUserId: String?, container: FrameLayout) {
        when (role) {
            "local" -> localContainer = container
            "remote" -> {
                this.remoteUserId = remoteUserId ?: this.remoteUserId
                remoteContainer = container
            }
        }
        val rtcEngine = ensureEngine()
        if (role == "local") {
            attachLocalView(rtcEngine)
        } else {
            attachRemoteView(rtcEngine)
        }
    }

    fun unbindVideoView(container: FrameLayout) {
        if (localContainer === container) {
            engine?.stopPreview()
            engine?.setLocalViewConfig(null as AliRtcVideoCanvas?, AliRtcVideoTrack.AliRtcVideoTrackCamera)
            localContainer = null
        }
        if (remoteContainer === container) {
            remoteUserId?.let { userId ->
                engine?.setRemoteViewConfig(null as AliRtcVideoCanvas?, userId, AliRtcVideoTrack.AliRtcVideoTrackCamera)
            }
            remoteContainer = null
        }
        container.removeAllViews()
    }

    private fun attachLocalView(rtcEngine: AliRtcEngine) {
        val container = localContainer ?: return
        container.removeAllViews()
        val renderView = rtcEngine.createRenderSurfaceView(context)
        container.addView(renderView, matchParentLayoutParams())
        val canvas = AliRtcVideoCanvas()
        canvas.view = renderView
        canvas.renderMode = AliRtcRenderMode.AliRtcRenderModeAuto
        rtcEngine.setLocalViewConfig(canvas, AliRtcVideoTrack.AliRtcVideoTrackCamera)
        rtcEngine.startPreview()
    }

    private fun attachRemoteView(rtcEngine: AliRtcEngine) {
        val container = remoteContainer ?: return
        val userId = remoteUserId ?: return
        container.removeAllViews()
        val renderView = rtcEngine.createRenderSurfaceView(context)
        container.addView(renderView, matchParentLayoutParams())
        val canvas = AliRtcVideoCanvas()
        canvas.view = renderView
        canvas.renderMode = AliRtcRenderMode.AliRtcRenderModeAuto
        rtcEngine.setRemoteViewConfig(canvas, userId, AliRtcVideoTrack.AliRtcVideoTrackCamera)
    }

    private fun subscribeRemoteMedia(rtcEngine: AliRtcEngine, userId: String) {
        rtcEngine.subscribeRemoteMediaStream(
            userId,
            AliRtcVideoTrack.AliRtcVideoTrackCamera,
            AliRtcAudioTrack.AliRtcAudioTrackMic,
        )
    }

    private fun matchParentLayoutParams(): FrameLayout.LayoutParams {
        return FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
    }

    private fun requireString(arguments: Map<*, *>, key: String): String {
        val value = arguments[key] as? String
        require(!value.isNullOrBlank()) { "missing rtc $key" }
        return value
    }

    private fun requireLong(arguments: Map<*, *>, key: String): Long {
        return when (val value = arguments[key]) {
            is Int -> value.toLong()
            is Long -> value
            is Number -> value.toLong()
            else -> throw IllegalArgumentException("missing rtc $key")
        }
    }

    private fun requireInt(arguments: Map<*, *>, key: String): Int {
        return when (val value = arguments[key]) {
            is Int -> value
            is Long -> value.toInt()
            is Number -> value.toInt()
            else -> throw IllegalArgumentException("missing rtc $key")
        }
    }

    private companion object {
        const val CHANNEL_NAME = "petnote/rtc"
        const val MEDIA_PERMISSION_REQUEST_CODE = 9421
        val mediaPermissions = arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO,
        )
    }
}
