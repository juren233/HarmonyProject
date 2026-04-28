package com.krustykrab.petnote

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PetNoteAiSecretStoreBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "petnote/ai_secret_store"
        private const val FILE_NAME = "petnote_ai_secret_store"
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var cachedPreferences: SharedPreferences? = null
    private var preferencesResolved = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isAvailable())
            "readKey" -> {
                val configId = (call.arguments as? Map<*, *>)?.get("configId") as? String
                result.success(configId?.let { preferences()?.getString(it, null) })
            }
            "hasKeys" -> {
                val configIds = (call.arguments as? Map<*, *>)?.get("configIds") as? List<*>
                val prefs = preferences()
                val states = mutableMapOf<String, Boolean>()
                configIds?.forEach { value ->
                    val configId = value as? String ?: return@forEach
                    states[configId] = prefs?.getString(configId, null)?.isNotEmpty() == true
                }
                result.success(states)
            }
            "writeKey" -> {
                val arguments = call.arguments as? Map<*, *>
                val configId = arguments?.get("configId") as? String
                val value = arguments?.get("value") as? String
                val prefs = preferences()
                if (configId.isNullOrEmpty() || value == null || prefs == null) {
                    result.success(null)
                    return
                }
                prefs.edit().putString(configId, value).apply()
                result.success(null)
            }
            "deleteKey" -> {
                val configId = (call.arguments as? Map<*, *>)?.get("configId") as? String
                val prefs = preferences()
                if (configId.isNullOrEmpty() || prefs == null) {
                    result.success(null)
                    return
                }
                prefs.edit().remove(configId).apply()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun isAvailable(): Boolean = preferences() != null

    private fun preferences(): SharedPreferences? {
        if (preferencesResolved) {
            return cachedPreferences
        }
        preferencesResolved = true
        cachedPreferences = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            null
        } else {
            try {
                val masterKey = MasterKey.Builder(context)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
                EncryptedSharedPreferences.create(
                    context,
                    FILE_NAME,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                )
            } catch (_: Throwable) {
                null
            }
        }
        return cachedPreferences
    }
}
