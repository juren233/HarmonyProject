package com.krustykrab.petnote

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray

data class PetNoteScheduledNotification(
    val key: String,
    val scheduledAtEpochMs: Long,
    val title: String,
    val body: String,
    val payloadJson: String,
)

object PetNoteNotificationScheduler {
    private const val LOG_TAG = "PetNoteNotification"
    private const val FLUTTER_SHARED_PREFERENCES = "FlutterSharedPreferences"
    private const val SNAPSHOT_STORAGE_KEY = "flutter.notification_jobs_snapshot_v1"

    fun exactAlarmStatus(context: Context): String {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return when {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S -> "available"
            alarmManager.canScheduleExactAlarms() -> "available"
            else -> "unavailable"
        }
    }

    fun scheduleNotification(
        context: Context,
        notification: PetNoteScheduledNotification,
    ) {
        val receiverIntent = Intent(context, PetNoteNotificationReceiver::class.java).apply {
            putExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_KEY, notification.key)
            putExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_TITLE, notification.title)
            putExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_BODY, notification.body)
            putExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_PAYLOAD, notification.payloadJson)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notification.key.hashCode(),
            receiverIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAtMillis = maxOf(System.currentTimeMillis() + 1_000L, notification.scheduledAtEpochMs)
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !alarmManager.canScheduleExactAlarms() -> {
                Log.w(
                    LOG_TAG,
                    "Exact alarm unavailable, falling back to inexact scheduling for ${notification.key}.",
                )
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent,
                )
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent,
                )
            }
            else -> {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
        }
    }

    fun cancelNotification(context: Context, key: String) {
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

    fun restorePersistedNotifications(
        context: Context,
        reason: String,
    ) {
        val restored = loadPersistedNotifications(context)
            .filter { it.scheduledAtEpochMs > System.currentTimeMillis() }
            .onEach { notification ->
                cancelNotification(context, notification.key)
                scheduleNotification(context, notification)
            }
            .count()
        Log.i(LOG_TAG, "Restored $restored notifications after $reason.")
    }

    private fun loadPersistedNotifications(context: Context): List<PetNoteScheduledNotification> {
        val raw = context
            .getSharedPreferences(FLUTTER_SHARED_PREFERENCES, Context.MODE_PRIVATE)
            .getString(SNAPSHOT_STORAGE_KEY, null)
            ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val payload = item.optJSONObject("payload")
                    val payloadJson = payload?.toString() ?: continue
                    val key = item.optString("key").ifBlank {
                        payload.optString("sourceType")
                            ?.let { sourceType ->
                                "$sourceType:${payload.optString("sourceId")}"
                            }
                            .orEmpty()
                    }
                    if (key.isBlank()) {
                        continue
                    }
                    add(
                        PetNoteScheduledNotification(
                            key = key,
                            scheduledAtEpochMs = item.optLong("scheduledAtEpochMs"),
                            title = item.optString("title"),
                            body = item.optString("body"),
                            payloadJson = payloadJson,
                        ),
                    )
                }
            }
        } catch (error: Throwable) {
            Log.e(LOG_TAG, "Failed to parse persisted notification snapshot.", error)
            emptyList()
        }
    }
}
