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

  /// Plays a single short "I'm listening" tone — exactly one per capture
  /// session in the on-device voice lifecycle (the old system SpeechRecognizer
  /// produced its own start beep; sherpa on-device does not, so we play our own).
  /// Native handler (`playDing`) is added on the device-verify pass; until then
  /// this is a swallowed no-op like the rest of the channel.
  Future<void> ding() async {
    try {
      await _channel.invokeMethod('playDing');
    } catch (e) {
      debugPrint('AudioBeepChannel.playDing failed: $e');
    }
  }

  Future<void> _set(bool suppressed) async {
    try {
      await _channel.invokeMethod('setBeepSuppressed', suppressed);
    } catch (e) {
      debugPrint('AudioBeepChannel.setBeepSuppressed($suppressed) failed: $e');
    }
  }
}
