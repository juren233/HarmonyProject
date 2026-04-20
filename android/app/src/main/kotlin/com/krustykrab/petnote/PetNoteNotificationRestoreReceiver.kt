package com.krustykrab.petnote

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class PetNoteNotificationRestoreReceiver : BroadcastReceiver() {
    companion object {
        private const val LOG_TAG = "PetNoteNotification"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: "unknown"
        if (
            action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !PetNoteNotificationScheduler.canScheduleExactAlarms(context)
        ) {
            Log.w(LOG_TAG, "Skip restore because exact alarm permission is still unavailable.")
            return
        }
        PetNoteNotificationScheduler.restorePersistedNotifications(context, action)
    }
}