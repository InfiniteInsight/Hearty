import 'dart:async';

/// Outcome of a finished STT turn.
class SttResult {
  const SttResult({required this.transcript, this.ok = true, this.error});
  final String transcript;
  final bool ok;
  final String? error;
}

/// Engine-agnostic streaming speech-to-text for one capture session.
///
/// Implementations: [OnDeviceSttEngine] (sherpa on a background isolate) and,
/// in Plan C, a cloud engine. The lifecycle in `VoiceNotifier` drives this
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
