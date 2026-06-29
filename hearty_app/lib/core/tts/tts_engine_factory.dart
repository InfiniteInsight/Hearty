import 'tts_engine.dart';
import 'neural_tts_engine.dart';
import 'system_tts_engine.dart';

typedef TtsEngineBuilder = TtsEngine Function();

/// Builds and initializes the TTS engine to use.
///
/// Uses the bespoke NeuralTtsEngine (sherpa-onnx); if its init fails, falls back
/// to SystemTtsEngine with the platform default voice. The returned engine is
/// already initialized.
///
/// [neuralBuilder]/[systemBuilder] exist only for testing injection.
Future<TtsEngine> createTtsEngine({
  TtsEngineBuilder? neuralBuilder,
  TtsEngineBuilder? systemBuilder,
}) async {
  final neural = (neuralBuilder ?? () => NeuralTtsEngine())();
  if (await neural.init()) return neural;
  final sys = (systemBuilder ?? () => SystemTtsEngine())();
  await sys.init();
  return sys;
}
