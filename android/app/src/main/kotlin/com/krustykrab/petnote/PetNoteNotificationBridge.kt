package com.krustykrab.petnote

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class PetNoteNotificationBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "petnote/notifications"
        const val REQUEST_CODE_NOTIFICATIONS = 24037
        const val CHANNEL_ID = "petnote_care"
        const val LEGACY_CHANNEL_ID = "petnote_care_alerts"
        const val EXTRA_NOTIFICATION_KEY = "petnote_notification_key"
        const val EXTRA_NOTIFICATION_TITLE = "petnote_notification_title"
        const val EXTRA_NOTIFICATION_BODY = "petnote_notification_body"
        const val EXTRA_NOTIFICATION_PAYLOAD = "petnote_notification_payload"
    }

    private val context: Context = activity.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var initialLaunchIntent: Map<String, Any?>? = extractLaunchIntent(activity.intent)
    private var pendingForegroundTap: Map<String, Any?>? = null

    init {
        channel.setMethodCallHandler(this)
        createNotificationChannel()
        deleteLegacyNotificationChannel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                createNotificationChannel()
                deleteLegacyNotificationChannel()
                result.success(null)
            }
            "getPermissionState" -> result.success(permissionState())
            "hasHandledPermissionPrompt" -> result.success(hasHandledPermissionPrompt())
            "requestPermission" -> requestPermission(result)
            "scheduleLocalNotification" -> {
                scheduleLocalNotification(call.arguments as? Map<*, *>)
                result.success(null)
            }
            "cancelNotification" -> {
                cancelNotification(call.arguments as? String)
                result.success(null)
            }
            "getInitialLaunchIntent" -> {
                result.success(initialLaunchIntent)
                initialLaunchIntent = null
            }
            "consumeForegroundTap" -> {
                result.success(pendingForegroundTap)
                pendingForegroundTap = null
            }
            "registerPushToken" -> result.success(null)
            "openNotificationSettings" -> {
                result.success(openNotificationSettings())
            }
            "openExactAlarmSettings" -> {
                result.success(openExactAlarmSettings())
            }
            "getCapabilities" -> {
                result.success(
                    mapOf(
                        "exactAlarmStatus" to PetNoteNotificationScheduler.exactAlarmStatus(context),
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }

    fun handleIntent(intent: Intent?) {
        val payload = extractLaunchIntent(intent) ?: return
        pendingForegroundTap = payload
    }

    fun handlePermissionResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE_NOTIFICATIONS) {
            return false
        }
        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults.first() == PackageManager.PERMISSION_GRANTED
        val state = if (granted) "authorized" else "denied"
        val promptHandled = grantResults.isNotEmpty()
        result.success(permissionRequestResult(state, promptHandled))
        return true
    }

    private fun permissionState(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return "authorized"
        }
        return if (
            ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            "authorized"
        } else {
            "denied"
        }
    }


    private fun hasHandledPermissionPrompt(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return false
        }
        return try {
            val packageManagerClass = PackageManager::class.java
            val getPermissionFlagsMethod = packageManagerClass.getMethod(
                "getPermissionFlags",
                String::class.java,
                String::class.java,
                android.os.UserHandle::class.java,
            )
            val flagsValue = getPermissionFlagsMethod.invoke(
                activity.packageManager,
                Manifest.permission.POST_NOTIFICATIONS,
                activity.packageName,
                android.os.Process.myUserHandle(),
            ) as? Number ?: return false
            val userSetFlag = packageManagerClass.getField("FLAG_PERMISSION_USER_SET")
                .get(null) as? Number ?: return false
            val userFixedFlag = packageManagerClass.getField("FLAG_PERMISSION_USER_FIXED")
                .get(null) as? Number ?: return false
            val userDecisionFlags = userSetFlag.toLong() or userFixedFlag.toLong()
            flagsValue.toLong() and userDecisionFlags != 0L
        } catch (_: Exception) {
            false
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(permissionRequestResult("authorized", false))
            return
        }
        if (permissionState() == "authorized") {
            result.success(permissionRequestResult("authorized", false))
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_CODE_NOTIFICATIONS,
        )
    }


    private fun permissionRequestResult(state: String, promptHandled: Boolean): Map<String, Any> {
        return mapOf(
            "state" to state,
            "promptHandled" to promptHandled,
        )
    }

    private fun scheduleLocalNotification(arguments: Map<*, *>?) {
        val key = arguments?.get("key") as? String ?: return
        val scheduledAtEpochMs =
            (arguments["scheduledAtEpochMs"] as? Number)?.toLong() ?: return
        val title = arguments["title"] as? String ?: ""
        val body = arguments["body"] as? String ?: ""
        val payloadMap = arguments["payload"] as? Map<*, *> ?: emptyMap<String, Any?>()
        val payloadJson = JSONObject(payloadMap).toString()
        PetNoteNotificationScheduler.scheduleNotification(
            context = context,
            notification = PetNoteScheduledNotification(
                key = key,
                scheduledAtEpochMs = scheduledAtEpochMs,
                title = title,
                body = body,
                payloadJson = payloadJson,
            ),
        )
    }

    private fun cancelNotification(key: String?) {
        if (key.isNullOrEmpty()) {
            return
        }
        PetNoteNotificationScheduler.cancelNotification(context, key)
    }

    private fun openNotificationSettings(): String {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return startSettingsActivity(intent)
    }

    private fun openExactAlarmSettings(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return "unsupported"
        }
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return startSettingsActivity(intent)
    }

    private fun startSettingsActivity(intent: Intent): String {
        return try {
            context.startActivity(intent)
            "opened"
        } catch (_: Throwable) {
            "failed"
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "宠记提醒",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "宠记待办和提醒通知"
            enableVibration(true)
            setShowBadge(true)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun deleteLegacyNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
    }

    private fun extractLaunchIntent(intent: Intent?): Map<String, Any?>? {
        val payloadJson = intent?.getStringExtra(EXTRA_NOTIFICATION_PAYLOAD) ?: return null
        return try {
            val payloadObject = JSONObject(payloadJson)
            mapOf(
                "payload" to mapOf(
                    "sourceType" to payloadObject.optString("sourceType"),
                    "sourceId" to payloadObject.optString("sourceId"),
                    "petId" to payloadObject.optString("petId"),
                    "routeTarget" to payloadObject.optString("routeTarget"),
                ),
                "fromForeground" to false,
            )
        } catch (_: Throwable) {
            null
        }
    }
}