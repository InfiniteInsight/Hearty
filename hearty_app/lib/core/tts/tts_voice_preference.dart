import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kVoicePrefKey = 'tts_voice_name';

class TtsVoiceNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kVoicePrefKey);
  }

  Future<void> setVoice(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null) {
      await prefs.remove(_kVoicePrefKey);
    } else {
      await prefs.setString(_kVoicePrefKey, name);
    }
    state = AsyncData(name);
  }
}

final ttsVoiceProvider =
    AsyncNotifierProvider<TtsVoiceNotifier, String?>(TtsVoiceNotifier.new);
