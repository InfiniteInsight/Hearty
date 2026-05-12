package com.hearty.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.hearty.app.AnalysisWorker

class MainActivity : FlutterActivity() {

    companion object {
        const val ACTION_WAKE_WORD_DETECTED = "com.hearty.app.WAKE_WORD_DETECTED"
    }

    // Set before super.onCreate() so configureFlutterEngine can read it.
    private var pendingWakeWord = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        if (intent?.action == ACTION_WAKE_WORD_DETECTED) {
            pendingWakeWord = true
            applyShowWhenLocked()
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ACTION_WAKE_WORD_DETECTED) {
            applyShowWhenLocked()
            // Engine is already running — fire directly.
            flutterEngine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, HeartyWakeWordService.METHOD_CHANNEL)
                    .invokeMethod("wakeWordDetected", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HeartyWakeWordService.flutterBinaryMessenger = flutterEngine.dartExecutor.binaryMessenger

        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            startForegroundService(Intent(this, HeartyWakeWordService::class.java))
        }

        // Register nightly analysis job (deduped by WorkManager KEEP policy)
        AnalysisWorker.enqueuePeriodic(this, AnalysisWorker.DEFAULT_BASE_URL, authToken = null)

        // Method channel for Flutter to trigger an idle analysis run after logging
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hearty.app/analysis")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enqueueIdleAnalysis" -> {
                        AnalysisWorker.enqueueIdle(this, AnalysisWorker.DEFAULT_BASE_URL, authToken = null)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hearty.app/wake_word_control")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                            startForegroundService(Intent(this, HeartyWakeWordService::class.java))
                            result.success(null)
                        } else {
                            result.error("PERMISSION_DENIED", "RECORD_AUDIO not granted", null)
                        }
                    }
                    "stopService" -> {
                        stopService(Intent(this, HeartyWakeWordService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Cold-start: intent arrived before engine was ready.
        if (pendingWakeWord) {
            pendingWakeWord = false
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HeartyWakeWordService.METHOD_CHANNEL)
                .invokeMethod("wakeWordDetected", null)
        }
    }

    private fun applyShowWhenLocked() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }
}
