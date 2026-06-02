package com.hearty.app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) return
        // flutter.wake_word_enabled mirrors UserPreferences.wakeWordEnabled written
        // by notification_preferences_screen.dart via shared_preferences. Defaults
        // to true so existing installs that have never toggled the setting still
        // auto-start after a reboot.
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (prefs.getBoolean("flutter.wake_word_enabled", true)) {
            context.startForegroundService(Intent(context, HeartyWakeWordService::class.java))
        }
    }
}
