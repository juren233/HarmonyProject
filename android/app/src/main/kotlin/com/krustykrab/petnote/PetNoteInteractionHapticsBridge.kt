package com.krustykrab.petnote

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PetNoteInteractionHapticsBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "petnote/interaction_haptics"

        private const val DEFAULT_DELETE_HOLD_DURATION_MS = 560L
        private const val CONFIRM_CLICK_SCALE = 0.62f
        private const val CONFIRM_ONE_SHOT_DURATION_MS = 36L
        private const val CONFIRM_ONE_SHOT_AMPLITUDE = 210
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val vibrator: Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    private var hasActivePlayback = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "playDeleteHoldRamp" -> {
                val durationMs = call.argument<Int>("durationMs")?.toLong()
                    ?: DEFAULT_DELETE_HOLD_DURATION_MS
                playDeleteHoldRamp(durationMs)
                result.success(null)
            }

            "stopDeleteHoldRamp" -> {
                stopActivePlayback()
                result.success(null)
            }

            "playDeleteConfirmImpact" -> {
                playDeleteConfirmImpact()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun playDeleteHoldRamp(durationMs: Long) {
        val vibrator = vibrator
        if (vibrator == null || !vibrator.hasVibrator()) {
            return
        }
        stopActivePlayback()

        val effect =
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && vibrator.hasAmplitudeControl() -> {
                    VibrationEffect.createWaveform(
                        makeRampTimings(durationMs),
                        intArrayOf(0, 42, 72, 112, 156, 206, 0),
                        -1,
                    )
                }

                supportsRampPrimitives(vibrator) -> {
                    VibrationEffect
                        .startComposition()
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_LOW_TICK, 0.18f)
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, 0.24f, 92)
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, 0.34f, 92)
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.46f, 92)
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.58f, 92)
                        .compose()
                }

                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                    VibrationEffect.createWaveform(
                        makeRampTimings(durationMs),
                        intArrayOf(0, 255, 255, 255, 255, 255, 0),
                        -1,
                    )
                }

                else -> {
                    return
                }
            }

        vibrator.vibrate(effect)
        hasActivePlayback = true
    }

    private fun playDeleteConfirmImpact() {
        val vibrator = vibrator
        if (vibrator == null || !vibrator.hasVibrator()) {
            return
        }

        val effect =
            when {
                supportsClickPrimitive(vibrator) -> {
                    VibrationEffect
                        .startComposition()
                        .addPrimitive(
                            VibrationEffect.Composition.PRIMITIVE_CLICK,
                            CONFIRM_CLICK_SCALE,
                        ).compose()
                }

                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                    VibrationEffect.createOneShot(
                        CONFIRM_ONE_SHOT_DURATION_MS,
                        CONFIRM_ONE_SHOT_AMPLITUDE,
                    )
                }

                else -> {
                    return
                }
            }

        vibrator.vibrate(effect)
    }

    private fun stopActivePlayback() {
        if (!hasActivePlayback) {
            return
        }
        vibrator?.cancel()
        hasActivePlayback = false
    }

    private fun makeRampTimings(durationMs: Long): LongArray {
        val step = (durationMs.coerceAtLeast(180L) / 6).coerceAtLeast(20L)
        return longArrayOf(0, step, step, step, step, step, step)
    }

    private fun supportsRampPrimitives(vibrator: Vibrator): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return false
        }
        return vibrator
            .arePrimitivesSupported(
                VibrationEffect.Composition.PRIMITIVE_SLOW_RISE,
                VibrationEffect.Composition.PRIMITIVE_LOW_TICK,
                VibrationEffect.Composition.PRIMITIVE_TICK,
                VibrationEffect.Composition.PRIMITIVE_CLICK,
            ).all { it }
    }

    private fun supportsClickPrimitive(vibrator: Vibrator): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return false
        }
        return vibrator
            .arePrimitivesSupported(
                VibrationEffect.Composition.PRIMITIVE_CLICK,
            ).all { it }
    }
}
