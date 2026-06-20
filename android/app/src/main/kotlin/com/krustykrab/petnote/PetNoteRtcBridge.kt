package com.krustykrab.petnote

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ding.rtc.DingRtcAuthInfo
import com.ding.rtc.DingRtcEngine
import com.ding.rtc.DingRtcEngine.DingRtcAudioTrack
import com.ding.rtc.DingRtcEngine.DingRtcMuteLocalAudioMode
import com.ding.rtc.DingRtcEngine.DingRtcRenderMode
import com.ding.rtc.DingRtcEngine.DingRtcVideoCanvas
import com.ding.rtc.DingRtcEngine.DingRtcVideoDimensions
import com.ding.rtc.DingRtcEngine.DingRtcVideoEncoderConfiguration
import com.ding.rtc.DingRtcEngine.DingRtcVideoStreamType
import com.ding.rtc.DingRtcEngine.DingRtcVideoTrack
import com.ding.rtc.DingRtcEngineEventListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PetNoteRtcBridge(
    private val activity: Activity,
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var engine: DingRtcEngine? = null
    private var expectedRemoteUserId: String? = null
    private var activeRemoteUserId: String? = null
    private var localContainer: FrameLayout? = null
    private var remoteContainer: FrameLayout? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingJoinResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val joinTimeoutRunnable = Runnable {
        completeJoinWithError(-1, "join rtc channel timed out")
    }
    private val rtcEventListener = object : DingRtcEngineEventListener() {
        override fun onJoinChannelResult(result: Int, channel: String, userId: String, elapsed: Int) {
            Log.i(TAG, "onJoinChannelResult result=$result channel=$channel userId=$userId elapsed=$elapsed")
            mainHandler.post {
                handleJoinChannelResult(result, channel)
            }
        }

        override fun onOccurError(error: Int, msg: String) {
            Log.e(TAG, "onOccurError error=$error message=$msg")
            if (pendingJoinResult != null) {
                mainHandler.post {
                    completeJoinWithError(error, msg)
                }
            }
        }
        override fun onRemoteUserOnLineNotify(uid: String, elapsed: Int) {
            Log.i(TAG, "onRemoteUserOnLineNotify uid=$uid elapsed=$elapsed")
            handleRemoteMediaAvailable(uid)
        }

        override fun onRemoteTrackAvailableNotify(
            uid: String,
            audioTrack: DingRtcAudioTrack,
            videoTrack: DingRtcVideoTrack,
        ) {
            Log.i(TAG, "onRemoteTrackAvailableNotify uid=$uid audio=$audioTrack video=$videoTrack")
            handleRemoteMediaAvailable(uid)
        }

        override fun onFirstVideoPacketReceived(uid: String, videoTrack: DingRtcVideoTrack, timeCost: Int) {
            Log.i(TAG, "onFirstVideoPacketReceived uid=$uid video=$videoTrack timeCost=$timeCost")
        }

        override fun onFirstAudioPacketReceived(uid: String, timeCost: Int) {
            Log.i(TAG, "onFirstAudioPacketReceived uid=$uid timeCost=$timeCost")
        }

        override fun onFirstRemoteVideoFrameDrawn(
            uid: String,
            videoTrack: DingRtcVideoTrack,
            width: Int,
            height: Int,
            elapsed: Int,
        ) {
            Log.i(
                TAG,
                "onFirstRemoteVideoFrameDrawn uid=$uid video=$videoTrack size=${width}x$height elapsed=$elapsed",
            )
        }

        override fun onApiCalledExecuted(error: Int, api: String, result: String) {
            Log.i(TAG, "onCalledApiExecuted error=$error api=$api result=$result")
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
                    join(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                }
                "leave" -> {
                    cancelPendingJoin("rtc join was cancelled by leave")
                    resetRtcSession()
                    result.success(null)
                }
                "toggleCamera" -> {
                    val enabled = (call.argument<Boolean>("enabled") ?: true)
                    engine?.muteLocalCamera(!enabled, DingRtcVideoTrack.DingRtcVideoTrackCamera)
                    result.success(null)
                }
                "toggleMicrophone" -> {
                    val enabled = (call.argument<Boolean>("enabled") ?: true)
                    engine?.muteLocalMic(!enabled, DingRtcMuteLocalAudioMode.DingRtcMuteOnlyMicAudioMode)
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
                    cancelPendingJoin("rtc join was cancelled by dispose")
                    resetRtcSession()
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
        cancelPendingJoin("rtc join was cancelled by close")
        resetRtcSession()
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

    private fun ensureEngine(): DingRtcEngine {
        val existing = engine
        if (existing != null) {
            return existing
        }
        val created = DingRtcEngine.create(context, "")
        created.setRtcEngineEventListener(rtcEventListener)
        logResult("subscribeAllRemoteAudioStreams", created.subscribeAllRemoteAudioStreams(true))
        logResult("subscribeAllRemoteVideoStreams", created.subscribeAllRemoteVideoStreams(true))
        logResult(
            "setRemoteDefaultVideoStreamType",
            created.setRemoteDefaultVideoStreamType(DingRtcVideoStreamType.DingRtcVideoStreamTypeFHD),
        )
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

    private fun join(arguments: Map<*, *>, result: MethodChannel.Result) {
        pendingJoinResult?.error(
            "rtc_join_replaced",
            "rtc join was replaced by a new join request",
            null,
        )
        pendingJoinResult = result
        val rtcEngine = ensureEngine()
        configureVideoEncoder(rtcEngine, arguments)
        expectedRemoteUserId = requireString(arguments, "remoteUserId")
        activeRemoteUserId = null
        attachLocalView(rtcEngine)
        attachRemoteView(rtcEngine)
        val channelId = requireString(arguments, "channelId")
        val userId = requireString(arguments, "userId")
        val appId = requireString(arguments, "appId")
        val singleToken = requireString(arguments, "singleToken")
        Log.i(TAG, "join requested channelId=$channelId userId=$userId remoteUserId=$expectedRemoteUserId")
        val authInfo = DingRtcAuthInfo()
        authInfo.appId = appId
        authInfo.channelId = channelId
        authInfo.userId = userId
        authInfo.token = singleToken
        val userName = userId
        val joinResult = rtcEngine.joinChannel(authInfo, userName)
        logResult("joinChannel", joinResult)
        if (joinResult != 0) {
            completeJoinWithError(joinResult, "join rtc channel failed: $joinResult")
            return
        }
        mainHandler.removeCallbacks(joinTimeoutRunnable)
        mainHandler.postDelayed(joinTimeoutRunnable, JOIN_TIMEOUT_MS)
    }

    private fun handleJoinChannelResult(result: Int, channel: String) {
        val pendingResult = pendingJoinResult ?: return
        if (result != 0) {
            completeJoinWithError(result, "join rtc channel failed asynchronously: $result channel=$channel")
            return
        }
        val rtcEngine = engine
        if (rtcEngine == null) {
            completeJoinWithError(0, "join rtc channel succeeded after engine was released")
            return
        }
        logResult("publishLocalAudioStream", rtcEngine.publishLocalAudioStream(true))
        logResult("publishLocalVideoStream", rtcEngine.publishLocalVideoStream(true))
        logResult("subscribeAllRemoteAudioStreams", rtcEngine.subscribeAllRemoteAudioStreams(true))
        logResult("subscribeAllRemoteVideoStreams", rtcEngine.subscribeAllRemoteVideoStreams(true))
        expectedRemoteUserId?.let { userId -> subscribeRemoteMedia(rtcEngine, userId) }
        pendingJoinResult = null
        mainHandler.removeCallbacks(joinTimeoutRunnable)
        pendingResult.success(null)
    }

    private fun completeJoinWithError(code: Int, message: String) {
        val pendingResult = pendingJoinResult ?: return
        pendingJoinResult = null
        mainHandler.removeCallbacks(joinTimeoutRunnable)
        resetRtcSession()
        pendingResult.error("rtc_join_failed", "$message (code=$code)", null)
    }

    private fun cancelPendingJoin(message: String) {
        val pendingResult = pendingJoinResult ?: return
        pendingJoinResult = null
        mainHandler.removeCallbacks(joinTimeoutRunnable)
        pendingResult.error("rtc_join_cancelled", message, null)
    }

    private fun configureVideoEncoder(rtcEngine: DingRtcEngine, arguments: Map<*, *>) {
        val width = requireInt(arguments, "videoWidth")
        val height = requireInt(arguments, "videoHeight")
        require(width == 1280 && height == 720) { "rtc video quality must be 720P" }
        val config = DingRtcVideoEncoderConfiguration()
        config.dimensions = DingRtcVideoDimensions(width, height)
        rtcEngine.setVideoEncoderConfiguration(config)
        Log.i(TAG, "setVideoEncoderConfiguration result=0")
    }

    private fun resetRtcSession() {
        val rtcEngine = engine ?: return
        Log.i(TAG, "resetRtcSession")
        logResult("stopPreview", rtcEngine.stopPreview())
        logResult(
            "clearLocalViewConfig",
            rtcEngine.setLocalViewConfig(null as DingRtcVideoCanvas?, DingRtcVideoTrack.DingRtcVideoTrackCamera),
        )
        currentRemoteUserId()?.let { userId ->
            logResult(
                "clearRemoteViewConfig",
                rtcEngine.setRemoteViewConfig(null as DingRtcVideoCanvas?, userId, DingRtcVideoTrack.DingRtcVideoTrackCamera),
            )
        }
        logResult("leaveChannel", rtcEngine.leaveChannel())
        localContainer?.removeAllViews()
        remoteContainer?.removeAllViews()
        expectedRemoteUserId = null
        activeRemoteUserId = null
    }

    private fun handleRemoteMediaAvailable(uid: String) {
        activity.runOnUiThread {
            val rtcEngine = engine ?: return@runOnUiThread
            activeRemoteUserId = uid
            subscribeRemoteMedia(rtcEngine, uid)
            attachRemoteView(rtcEngine)
        }
    }

    fun bindVideoView(role: String, remoteUserId: String?, container: FrameLayout) {
        when (role) {
            "local" -> localContainer = container
            "remote" -> {
                expectedRemoteUserId = remoteUserId ?: expectedRemoteUserId
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
            engine?.setLocalViewConfig(null as DingRtcVideoCanvas?, DingRtcVideoTrack.DingRtcVideoTrackCamera)
            localContainer = null
        }
        if (remoteContainer === container) {
            currentRemoteUserId()?.let { userId ->
                engine?.setRemoteViewConfig(null as DingRtcVideoCanvas?, userId, DingRtcVideoTrack.DingRtcVideoTrackCamera)
            }
            remoteContainer = null
        }
        container.removeAllViews()
    }

    private fun attachLocalView(rtcEngine: DingRtcEngine) {
        val container = localContainer ?: return
        container.removeAllViews()
        val renderView = DingRtcEngine.createRenderSurfaceView(context)
        container.addView(renderView, matchParentLayoutParams())
        val canvas = DingRtcVideoCanvas()
        canvas.view = renderView
        canvas.renderMode = DingRtcRenderMode.DingRtcRenderModeAuto
        logResult("setLocalViewConfig", rtcEngine.setLocalViewConfig(canvas, DingRtcVideoTrack.DingRtcVideoTrackCamera))
        logResult("startPreview", rtcEngine.startPreview())
    }

    private fun attachRemoteView(rtcEngine: DingRtcEngine) {
        val container = remoteContainer ?: return
        val userId = currentRemoteUserId() ?: return
        container.removeAllViews()
        val renderView = DingRtcEngine.createRenderSurfaceView(context)
        container.addView(renderView, matchParentLayoutParams())
        val canvas = DingRtcVideoCanvas()
        canvas.view = renderView
        canvas.renderMode = DingRtcRenderMode.DingRtcRenderModeAuto
        logResult("setRemoteViewConfig", rtcEngine.setRemoteViewConfig(canvas, userId, DingRtcVideoTrack.DingRtcVideoTrackCamera))
    }

    private fun subscribeRemoteMedia(rtcEngine: DingRtcEngine, userId: String) {
        logResult(
            "subscribeRemoteVideoStream",
            rtcEngine.subscribeRemoteVideoStream(
                userId,
                DingRtcVideoTrack.DingRtcVideoTrackCamera,
                true,
            ),
        )
    }

    private fun logResult(operation: String, code: Int) {
        val message = "$operation result=$code"
        if (code == 0) {
            Log.i(TAG, message)
        } else {
            Log.e(TAG, message)
        }
    }

    private fun currentRemoteUserId(): String? {
        return activeRemoteUserId ?: expectedRemoteUserId
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

    private fun requireNullableString(arguments: Map<*, *>, key: String): String? {
        return arguments[key] as? String
    }

    private fun requireLong(arguments: Map<*, *>, key: String): Long {
        return when (val value = arguments[key]) {
            is Long -> value
            is Int -> value.toLong()
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
        const val TAG = "PetNoteRtc"
        const val CHANNEL_NAME = "petnote/rtc"
        const val MEDIA_PERMISSION_REQUEST_CODE = 9421
        const val JOIN_TIMEOUT_MS = 15000L
        val mediaPermissions = arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO,
        )
    }
}
