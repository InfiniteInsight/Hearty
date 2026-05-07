import 'package:flutter/services.dart';

/// Wraps the MethodChannel to the Kotlin HeartyWakeWordService.
class WakeWordChannel {
  static const _channel = MethodChannel('com.hearty.app/wake_word');

  static void onWakeWordDetected(void Function() callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'wakeWordDetected') callback();
    });
  }

  static Future<void> startListening() =>
      _channel.invokeMethod('startListening');

  static Future<void> stopListening() =>
      _channel.invokeMethod('stopListening');
}
