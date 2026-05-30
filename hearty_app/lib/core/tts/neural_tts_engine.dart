import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'tts_engine.dart';
import 'tts_audio_utils.dart';

class NeuralTtsEngine implements TtsEngine {
  NeuralTtsEngine(
      {this.modelAssetDir = 'assets/tts/vits-piper-en_US-libritts_r-medium'});
  final String modelAssetDir;

  sherpa.OfflineTts? _tts;
  final AudioPlayer _player = AudioPlayer();
  VoidCallback? _onDone;
  TtsStyle _style = TtsStyle.warm;
  bool _completionWired = false;

  @override
  Future<bool> init({String? voiceName}) async {
    try {
      final dir = await copyModelAssets(modelAssetDir);
      if (!Directory(dir).existsSync()) return false;
      // Confirm the model file actually exists before constructing the engine.
      if (!File('$dir/en_US-libritts_r-medium.onnx').existsSync()) return false;
      sherpa.initBindings();
      final vits = sherpa.OfflineTtsVitsModelConfig(
        model: '$dir/en_US-libritts_r-medium.onnx',
        tokens: '$dir/tokens.txt',
        dataDir: '$dir/espeak-ng-data',
      );
      final model = sherpa.OfflineTtsModelConfig(vits: vits, numThreads: 2);
      _tts = sherpa.OfflineTts(
          sherpa.OfflineTtsConfig(model: model, maxNumSenetences: 1));
      if (!_completionWired) {
        _player.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) _onDone?.call();
        });
        _completionWired = true;
      }
      return true;
    } catch (e) {
      debugPrint('NeuralTtsEngine init failed: $e');
      return false;
    }
  }

  @override
  Future<void> speak(String text) async {
    final tts = _tts;
    if (tts == null) return;
    final speed = _style == TtsStyle.concise ? 1.1 : 0.95;
    final audio = tts.generate(text: text, sid: 0, speed: speed);
    final wav = pcmToWav(audio.samples, audio.sampleRate);
    final tmp = File('${Directory.systemTemp.path}/hearty_tts.wav');
    await tmp.writeAsBytes(wav, flush: true);
    await _player.stop();
    await _player.setFilePath(tmp.path);
    await _player.play();
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  void setCompletionHandler(VoidCallback onDone) => _onDone = onDone;

  @override
  Future<void> setStyle(TtsStyle style) async => _style = style;

  @override
  Future<void> dispose() async {
    await _player.dispose();
    _tts?.free();
    _tts = null;
  }
}
