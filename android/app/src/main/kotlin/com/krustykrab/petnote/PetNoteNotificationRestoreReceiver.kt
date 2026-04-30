package com.krustykrab.petnote

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class PetNoteNotificationRestoreReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: "unknown"
        if (
            action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !PetNoteNotificationScheduler.canScheduleExactAlarms(context)
        ) {
            return
        }
        PetNoteNotificationScheduler.restorePersistedNotifications(context, action)
    }
}