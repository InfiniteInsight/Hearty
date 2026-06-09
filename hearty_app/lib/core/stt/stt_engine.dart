import 'dart:async';

/// Outcome of a finished STT turn.
class SttResult {
  const SttResult({required this.transcript, this.ok = true, this.error});
  final String transcript;
  final bool ok;
  final String? error;
}

/// Thrown by engine selection when the chosen on-device model isn't downloaded/
/// warm yet. The capture path must catch this and drop to manual (text entry)
/// rather than block on a download — the model is fetched + warmed out-of-band.
class SttNotReadyException implements Exception {
  const SttNotReadyException();
  @override
  String toString() => 'SttNotReadyException: on-device model not ready';
}

/// Engine-agnostic speech-to-text for one capture session.
///
/// Implementations: [OnDeviceBatchSttEngine] (sherpa on a background isolate)
/// and [CloudSttEngine]. The lifecycle in `VoiceNotifier` drives this
/// interface, so it never depends on a concrete engine.
abstract class SttEngine {
  /// Begin capturing. Live interim text arrives on [partials]. If
  /// [onAutoSubmit] is provided, the engine invokes it when its silence policy
  /// decides the turn is over (the caller then calls [stop]); pass null to
  /// disable auto-submit (manual / tap-to-confirm only).
  Future<void> start({void Function()? onAutoSubmit});

  /// Live interim transcript. Empty strings are allowed; never null.
  Stream<String> get partials;

  /// Stop capturing and return the final transcript.
  Future<SttResult> stop();

  /// Release all resources (mic, isolate). Safe to call repeatedly.
  Future<void> dispose();
}
