import 'package:flutter/foundation.dart';
import 'package:hearty_app/core/tts/tts_engine.dart';

class FakeTtsEngine implements TtsEngine {
  String? spokenText;
  VoidCallback? _onDone;
  final bool fireCompletionOnSpeak;
  FakeTtsEngine({this.fireCompletionOnSpeak = true});

  @override
  Future<bool> init({String? voiceName}) async => true;

  @override
  Future<void> speak(String text) async {
    spokenText = text;
    if (fireCompletionOnSpeak) _onDone?.call();
  }

  @override
  Future<void> stop() async {}

  @override
  void setCompletionHandler(VoidCallback onDone) => _onDone = onDone;

  /// Manually fire the completion callback. In production both natural TTS
  /// completion AND `stop()` (called by dismiss/stopSpeaking) fire it — tests
  /// use this to simulate completion arriving after a cancel.
  void fireCompletion() => _onDone?.call();

  @override
  Future<void> setStyle(TtsStyle style) async {}

  @override
  Future<void> dispose() async {}
}
