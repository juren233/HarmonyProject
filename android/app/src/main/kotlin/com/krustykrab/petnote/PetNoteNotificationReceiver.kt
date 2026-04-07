package com.krustykrab.petnote

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

class PetNoteNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val key =
            intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_KEY) ?: return
        val title = intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_TITLE) ?: "宠记提醒"
        val body = intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_BODY) ?: ""
        val payload = intent.getStringExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_PAYLOAD)

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                if (payload != null) {
                    putExtra(PetNoteNotificationBridge.EXTRA_NOTIFICATION_PAYLOAD, payload)
                }
            }
            ?: return

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
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(contentIntent)
            .build()

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(key.hashCode(), notification)
    }
}
