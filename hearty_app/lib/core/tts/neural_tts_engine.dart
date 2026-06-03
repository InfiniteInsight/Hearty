import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'tts_engine.dart';
import 'tts_audio_utils.dart';

class NeuralTtsEngine implements TtsEngine {
  NeuralTtsEngine({this.modelAssetDir = 'assets/tts/hearty-neutral'});
  final String modelAssetDir;

  /// Runtime pronunciation overrides for words espeak-ng phonemizes correctly
  /// but the (early-checkpoint) neural voice renders imprecisely. Keys are
  /// matched case-insensitively on whole words and replaced before synthesis.
  /// `caffeine` -> `caffeen`: the long /iː/ otherwise comes out short ("caffene").
  static const Map<String, String> _pronunciationFixes = {
    'caffeine': 'caffeen',
  };

  String _applyPronunciationFixes(String text) {
    var out = text;
    _pronunciationFixes.forEach((from, to) {
      out = out.replaceAll(
        RegExp('\\b${RegExp.escape(from)}\\b', caseSensitive: false),
        to,
      );
    });
    return out;
  }

  sherpa.OfflineTts? _tts;
  final AudioPlayer _player = AudioPlayer();
  VoidCallback? _onDone;
  TtsStyle _style = TtsStyle.warm;
  bool _completionWired = false;
  // just_audio re-emits player state while it remains in `completed` (and the
  // follow-up mic grabbing the audio device pokes it). Edge-detect so a single
  // utterance fires _onDone exactly once — otherwise the follow-up flow gets
  // re-armed repeatedly (listening "ding storm").
  bool _completedSignaled = false;

  @override
  Future<bool> init({String? voiceName}) async {
    try {
      final dir = await copyModelAssets(modelAssetDir);
      if (!Directory(dir).existsSync()) return false;
      // Confirm the model file actually exists before constructing the engine.
      if (!File('$dir/hearty-neutral.onnx').existsSync()) return false;
      sherpa.initBindings();
      final vits = sherpa.OfflineTtsVitsModelConfig(
        model: '$dir/hearty-neutral.onnx',
        tokens: '$dir/tokens.txt',
        dataDir: '$dir/espeak-ng-data',
      );
      final model = sherpa.OfflineTtsModelConfig(vits: vits, numThreads: 2);
      _tts = sherpa.OfflineTts(
          sherpa.OfflineTtsConfig(model: model, maxNumSenetences: 1));
      if (!_completionWired) {
        _player.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) {
            if (!_completedSignaled) {
              _completedSignaled = true;
              _onDone?.call();
            }
          } else {
            _completedSignaled = false;
          }
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
    // +8% baseline (1.08) — user-approved ep24 tempo (2026-06-02); concise a touch snappier.
    final speed = _style == TtsStyle.concise ? 1.18 : 1.08;
    final audio =
        tts.generate(text: _applyPronunciationFixes(text), sid: 0, speed: speed);
    final wav = pcmToWav(audio.samples, audio.sampleRate);
    final tmp = File('${Directory.systemTemp.path}/hearty_tts.wav');
    await tmp.writeAsBytes(wav, flush: true);
    _completedSignaled = false;
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
