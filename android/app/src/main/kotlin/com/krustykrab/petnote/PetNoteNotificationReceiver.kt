package com.krustykrab.petnote

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class PetNoteNotificationReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val key =
            intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_KEY) ?: return
        val title = intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_TITLE) ?: "宠记提醒"
        val body = intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_BODY) ?: ""
        val payload = intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_PAYLOAD)

        if (!hasNotificationPermission(context)) {
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
        } catch (error: SecurityException) {
        } catch (error: Throwable) {
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
