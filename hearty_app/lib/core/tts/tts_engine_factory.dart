import 'tts_engine.dart';
import 'neural_tts_engine.dart';
import 'system_tts_engine.dart';

typedef TtsEngineBuilder = TtsEngine Function();

/// Builds and initializes the TTS engine to use.
///
/// Order: if [systemVoiceOverride] is set, the user has explicitly chosen a
/// system voice in advanced settings, so use SystemTtsEngine directly.
/// Otherwise try NeuralTtsEngine; if its init fails, fall back to
/// SystemTtsEngine. The returned engine is already initialized.
///
/// [neuralBuilder]/[systemBuilder] exist only for testing injection.
Future<TtsEngine> createTtsEngine({
  String? systemVoiceOverride,
  TtsEngineBuilder? neuralBuilder,
  TtsEngineBuilder? systemBuilder,
}) async {
  if (systemVoiceOverride != null) {
    final sys = (systemBuilder ?? () => SystemTtsEngine())();
    await sys.init(voiceName: systemVoiceOverride);
    return sys;
  }
  final neural = (neuralBuilder ?? () => NeuralTtsEngine())();
  if (await neural.init()) return neural;
  final sys = (systemBuilder ?? () => SystemTtsEngine())();
  await sys.init();
  return sys;
}
