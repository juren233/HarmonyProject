package com.krustykrab.petnote

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                createNotificationChannel()
                result.success(null)
            }
            "getPermissionState" -> result.success(permissionState())
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
                openNotificationSettings()
                result.success(null)
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
        result.success(if (granted) "authorized" else "denied")
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

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success("authorized")
            return
        }
        if (permissionState() == "authorized") {
            result.success("authorized")
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_CODE_NOTIFICATIONS,
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
        val receiverIntent = Intent(context, PetNoteNotificationReceiver::class.java).apply {
            putExtra(EXTRA_NOTIFICATION_KEY, key)
            putExtra(EXTRA_NOTIFICATION_TITLE, title)
            putExtra(EXTRA_NOTIFICATION_BODY, body)
            putExtra(EXTRA_NOTIFICATION_PAYLOAD, payloadJson)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            key.hashCode(),
            receiverIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAtMillis = maxOf(System.currentTimeMillis() + 1_000L, scheduledAtEpochMs)
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms())
        ) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
    }

    private fun cancelNotification(key: String?) {
        if (key.isNullOrEmpty()) {
            return
        }
        val receiverIntent = Intent(context, PetNoteNotificationReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            key.hashCode(),
            receiverIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(key.hashCode())
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
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
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "宠记待办和提醒通知"
        }
        notificationManager.createNotificationChannel(channel)
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
