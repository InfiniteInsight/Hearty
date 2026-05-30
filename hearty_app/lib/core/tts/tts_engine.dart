import 'package:flutter/foundation.dart';

enum TtsStyle { warm, concise }

/// Engine-agnostic text-to-speech seam used by VoiceNotifier.
/// Implementations: NeuralTtsEngine (sherpa-onnx, default),
/// SystemTtsEngine (flutter_tts, fallback).
abstract class TtsEngine {
  /// Prepare the engine. [voiceName] is an optional system-voice override
  /// (honored only by SystemTtsEngine). Must not throw; return false on
  /// unrecoverable init failure so the caller can fall back.
  Future<bool> init({String? voiceName});

  /// Speak [text]. Resolves when playback finishes. The completion handler
  /// (if set) also fires on finish.
  Future<void> speak(String text);

  /// Stop any in-progress speech immediately.
  Future<void> stop();

  /// Register a callback invoked when an utterance finishes playing.
  void setCompletionHandler(VoidCallback onDone);

  /// Apply delivery style (rate/pitch/contour). No-op until Phase 3.
  Future<void> setStyle(TtsStyle style);

  /// Release native resources.
  Future<void> dispose();
}
