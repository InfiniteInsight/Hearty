package com.hearty.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Give the wake word service access to the Flutter binary messenger
        // so it can call `wakeWordDetected` into Dart.
        HeartyWakeWordService.flutterBinaryMessenger = flutterEngine.dartExecutor.binaryMessenger
        val serviceIntent = Intent(this, HeartyWakeWordService::class.java)
        startForegroundService(serviceIntent)
    }
}
