package com.krustykrab.petnote

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class PetNoteNotificationReceiver : BroadcastReceiver() {
    companion object {
        private const val LOG_TAG = "PetNoteNotification"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val key =
            intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_KEY) ?: return
        val title = intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_TITLE) ?: "宠记提醒"
        val body = intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_BODY) ?: ""
        val payload = intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_PAYLOAD)

        Log.i(LOG_TAG, "Received notification alarm for $key.")
        if (!hasNotificationPermission(context)) {
            Log.w(LOG_TAG, "Skip notification $key because POST_NOTIFICATIONS is denied.")
            return
        }

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                if (payload != null) {
                    putExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_PAYLOAD, payload)
                }
            }
            ?: run {
                Log.w(LOG_TAG, "Skip notification $key because launch intent is unavailable.")
                return
            }

        val contentIntent = PendingIntent.getActivity(
            context,
            key.hashCode(),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(
            context,
            PetNoteNotificationBridge.CHANNEL_ID,
        )
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(contentIntent)
            .build()

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            manager.notify(key.hashCode(), notification)
            Log.i(LOG_TAG, "Posted notification $key on channel ${PetNoteNotificationBridge.CHANNEL_ID}.")
        } catch (error: SecurityException) {
            Log.e(LOG_TAG, "Failed to post notification $key because permission was rejected.", error)
        } catch (error: Throwable) {
            Log.e(LOG_TAG, "Failed to post notification $key.", error)
        }
    }

    private fun hasNotificationPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }
}
