import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_engine.dart';

class SystemTtsEngine implements TtsEngine {
  SystemTtsEngine({FlutterTts? ttsForTesting})
      : _tts = ttsForTesting ?? FlutterTts();
  final FlutterTts _tts;

  @override
  Future<bool> init({String? voiceName}) async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.7);
    await _tts.setPitch(1.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = voiceName ?? prefs.getString('tts_voice_name');
      if (saved != null) {
        await _tts.setVoice({'name': saved, 'locale': 'en-US'});
      }
    } catch (_) {
      // SharedPreferences unavailable (e.g. test env) — skip saved-voice load.
    }
    return true;
  }

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();

  @override
  void setCompletionHandler(VoidCallback onDone) =>
      _tts.setCompletionHandler(onDone);

  @override
  Future<void> setStyle(TtsStyle style) async {
    // System engine maps style to speech RATE only. Pitch-shifting a system
    // voice distorts formants, so we leave pitch alone.
    await _tts.setSpeechRate(style == TtsStyle.concise ? 0.8 : 0.7);
  }

  @override
  Future<void> dispose() => _tts.stop();
}
