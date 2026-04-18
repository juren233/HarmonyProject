package com.krustykrab.petnote

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PetNoteIntroHapticsBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "petnote/intro_haptics"
        private const val TAG = "PetNoteIntroHaptics"

        private const val LAUNCH_SLOW_RISE_SCALE = 0.34f
        private const val LAUNCH_QUICK_FALL_SCALE = 0.20f
        private const val ONBOARDING_SLOW_RISE_SCALE = 0.46f
        private const val ONBOARDING_QUICK_FALL_SCALE = 0.28f
        private const val BUTTON_TAP_CLICK_SCALE = 0.20f
        private const val BUTTON_TAP_ONE_SHOT_DURATION_MS = 18L
        private const val BUTTON_TAP_ONE_SHOT_AMPLITUDE = 84

        private val LAUNCH_FALLBACK_TIMINGS = longArrayOf(0, 34, 46, 66, 84)
        private val LAUNCH_FALLBACK_AMPLITUDES = intArrayOf(0, 72, 138, 188, 0)
        private val ONBOARDING_FALLBACK_TIMINGS = longArrayOf(0, 28, 44, 62, 86, 108)
        private val ONBOARDING_FALLBACK_AMPLITUDES = intArrayOf(0, 96, 162, 220, 148, 0)
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
            "playIntroLaunchContinuous" -> {
                Log.d(TAG, "Received playIntroLaunchContinuous")
                playLaunchHaptics()
                result.success(null)
            }

            "stopIntroLaunchContinuous" -> {
                Log.d(TAG, "Received stopIntroLaunchContinuous")
                stopActivePlayback()
                result.success(null)
            }

            "playIntroToOnboardingContinuous" -> {
                Log.d(TAG, "Received playIntroToOnboardingContinuous")
                playOnboardingHaptics()
                result.success(null)
            }

            "stopIntroToOnboardingContinuous" -> {
                Log.d(TAG, "Received stopIntroToOnboardingContinuous")
                stopActivePlayback()
                result.success(null)
            }

            "playIntroPrimaryButtonTap" -> {
                Log.d(TAG, "Received playIntroPrimaryButtonTap")
                playPrimaryButtonTapHaptics()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun playLaunchHaptics() {
        playHaptics(
            slowRiseScale = LAUNCH_SLOW_RISE_SCALE,
            quickFallScale = LAUNCH_QUICK_FALL_SCALE,
            fallbackTimings = LAUNCH_FALLBACK_TIMINGS,
            fallbackAmplitudes = LAUNCH_FALLBACK_AMPLITUDES,
            label = "launch",
        )
    }

    private fun playOnboardingHaptics() {
        playHaptics(
            slowRiseScale = ONBOARDING_SLOW_RISE_SCALE,
            quickFallScale = ONBOARDING_QUICK_FALL_SCALE,
            fallbackTimings = ONBOARDING_FALLBACK_TIMINGS,
            fallbackAmplitudes = ONBOARDING_FALLBACK_AMPLITUDES,
            label = "onboarding",
        )
    }

    private fun playPrimaryButtonTapHaptics() {
        val vibrator = vibrator
        if (vibrator == null || !vibrator.hasVibrator()) {
            Log.d(TAG, "Skip button-tap haptics: vibrator unavailable")
            return
        }

        val effect =
            when {
                supportsButtonTapPrimitive(vibrator) -> {
                    Log.d(TAG, "Playing button-tap haptics via click primitive")
                    VibrationEffect
                        .startComposition()
                        .addPrimitive(
                            VibrationEffect.Composition.PRIMITIVE_CLICK,
                            BUTTON_TAP_CLICK_SCALE,
                        ).compose()
                }

                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                    Log.d(TAG, "Playing button-tap haptics via one-shot fallback")
                    VibrationEffect.createOneShot(
                        BUTTON_TAP_ONE_SHOT_DURATION_MS,
                        BUTTON_TAP_ONE_SHOT_AMPLITUDE,
                    )
                }

                else -> {
                    Log.d(TAG, "Skip button-tap haptics: one-shot fallback unavailable")
                    return
                }
            }

        vibrator.vibrate(effect)
    }

    private fun playHaptics(
        slowRiseScale: Float,
        quickFallScale: Float,
        fallbackTimings: LongArray,
        fallbackAmplitudes: IntArray,
        label: String,
    ) {
        val vibrator = vibrator
        if (vibrator == null || !vibrator.hasVibrator()) {
            Log.d(TAG, "Skip $label haptics: vibrator unavailable")
            return
        }

        stopActivePlayback()

        val effect =
            when {
                supportsRichHaptics(vibrator) -> {
                    Log.d(TAG, "Playing $label haptics via composition primitives")
                    VibrationEffect
                        .startComposition()
                        .addPrimitive(VibrationEffect.Composition.PRIMITIVE_SLOW_RISE, slowRiseScale)
                        .addPrimitive(
                            VibrationEffect.Composition.PRIMITIVE_QUICK_FALL,
                            quickFallScale,
                        ).compose()
                }

                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                    Log.d(TAG, "Playing $label haptics via waveform fallback")
                    VibrationEffect.createWaveform(fallbackTimings, fallbackAmplitudes, -1)
                }

                else -> {
                    Log.d(TAG, "Skip $label haptics: waveform fallback unavailable")
                    return
                }
            }

        vibrator.vibrate(effect)
        hasActivePlayback = true
    }

    private fun stopActivePlayback() {
        if (!hasActivePlayback) {
            return
        }
        Log.d(TAG, "Stopping active intro haptics playback")
        vibrator?.cancel()
        hasActivePlayback = false
    }

    private fun supportsRichHaptics(vibrator: Vibrator): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return false
        }
        val primitivesSupported =
            vibrator
            .arePrimitivesSupported(
                VibrationEffect.Composition.PRIMITIVE_SLOW_RISE,
                VibrationEffect.Composition.PRIMITIVE_QUICK_FALL,
            ).all { it }
        Log.d(TAG, "Primitive support available: $primitivesSupported")
        return primitivesSupported
    }

    private fun supportsButtonTapPrimitive(vibrator: Vibrator): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return false
        }
        val primitiveSupported =
            vibrator
                .arePrimitivesSupported(
                    VibrationEffect.Composition.PRIMITIVE_CLICK,
                ).all { it }
        Log.d(TAG, "Button tap primitive support available: $primitiveSupported")
        return primitiveSupported
    }
}
