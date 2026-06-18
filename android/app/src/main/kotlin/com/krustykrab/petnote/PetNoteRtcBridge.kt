package com.krustykrab.petnote

import android.content.Context
import com.alivc.rtc.AliRtcAuthInfo
import com.alivc.rtc.AliRtcEngine
import com.alivc.rtc.AliRtcEngine.AliRtcMuteLocalAudioMode
import com.alivc.rtc.AliRtcEngine.AliRtcVideoDimensions
import com.alivc.rtc.AliRtcEngine.AliRtcVideoEncoderBitrate
import com.alivc.rtc.AliRtcEngine.AliRtcVideoEncoderConfiguration
import com.alivc.rtc.AliRtcEngine.AliRtcVideoTrack
import com.alivc.rtc.AliRtcEngineImpl
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PetNoteRtcBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var engine: AliRtcEngine? = null

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
        releaseEngine()
    }

    private fun ensureEngine(): AliRtcEngine {
        val existing = engine
        if (existing != null) {
            return existing
        }
        val created = AliRtcEngineImpl.getInstance(context)
        engine = created
        return created
    }

    private fun join(arguments: Map<*, *>) {
        val rtcEngine = ensureEngine()
        configureVideoEncoder(rtcEngine, arguments)
        val authInfo = AliRtcAuthInfo()
        authInfo.appId = requireString(arguments, "appId")
        authInfo.channelId = requireString(arguments, "channelId")
        authInfo.userId = requireString(arguments, "userId")
        authInfo.token = requireString(arguments, "token")
        authInfo.nonce = requireString(arguments, "nonce")
        authInfo.timestamp = requireLong(arguments, "timestamp")
        rtcEngine.joinChannel(authInfo, null)
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
        engine?.leaveChannel()
        engine?.destroy()
        engine = null
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
    }
}
