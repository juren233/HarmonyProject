package com.krustykrab.petnote

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PetNoteNotificationRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: "unknown"
        PetNoteNotificationScheduler.restorePersistedNotifications(context, action)
    }
}
