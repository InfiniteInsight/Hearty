import 'package:flutter/services.dart';

/// Wraps the MethodChannel to the Kotlin HeartyWakeWordService.
class WakeWordChannel {
  static const _channel = MethodChannel('com.hearty.app/wake_word');
  static const _controlChannel = MethodChannel('com.hearty.app/wake_word_control');

  static void onWakeWordDetected(void Function() callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'wakeWordDetected') callback();
    });
  }

  static Future<void> startListening() =>
      _channel.invokeMethod('startListening');

  static Future<void> stopListening() =>
      _channel.invokeMethod('stopListening');

  /// Start the foreground service. Call this after RECORD_AUDIO is granted.
  static Future<void> startService() =>
      _controlChannel.invokeMethod('startService');

  /// Stop the foreground service (e.g. when user disables wake word in settings).
  static Future<void> stopService() =>
      _controlChannel.invokeMethod('stopService');

  static void clearHandler() => _channel.setMethodCallHandler(null);
}
