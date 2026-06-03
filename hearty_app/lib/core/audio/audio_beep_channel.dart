import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Mutes/restores the candidate Android audio streams that the system
/// SpeechRecognizer plays its start/stop beeps on, so follow-up restart
/// sessions don't beep. Backed by the native `com.hearty.app/audio` channel.
/// Errors (incl. non-Android platforms with no handler) are swallowed —
/// callers never need try/catch; worst case is an un-suppressed beep.
class AudioBeepChannel {
  static const MethodChannel _channel = MethodChannel('com.hearty.app/audio');

  Future<void> suppress() => _set(true);
  Future<void> restore() => _set(false);

  Future<void> _set(bool suppressed) async {
    try {
      await _channel.invokeMethod('setBeepSuppressed', suppressed);
    } catch (e) {
      debugPrint('AudioBeepChannel.setBeepSuppressed($suppressed) failed: $e');
    }
  }
}
