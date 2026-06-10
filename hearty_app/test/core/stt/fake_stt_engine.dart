import 'dart:async';
import 'package:hearty_app/core/stt/stt_engine.dart';

/// Test double for [SttEngine]. Lets tests drive partials, simulate the
/// engine's silence policy firing, and control the final transcript.
class FakeSttEngine implements SttEngine {
  final _partials = StreamController<String>.broadcast();
  final _amplitude = StreamController<double>.broadcast();
  String nextTranscript = '';
  bool started = false;
  int startCount = 0;
  int disposeCount = 0;
  bool throwOnStart = false; // simulate model-missing / mic-denied
  bool nextResultOk = true; // simulate a failed (cloud) transcription
  void Function()? autoSubmit;

  @override
  Future<void> start({void Function()? onAutoSubmit}) async {
    startCount++;
    autoSubmit = onAutoSubmit;
    if (throwOnStart) throw StateError('fake engine start failed');
    started = true;
  }

  /// Test helper: push a live partial.
  void emitPartial(String text) => _partials.add(text);

  /// Test helper: push a live mic amplitude (raw linear RMS).
  void emitAmplitude(double rms) => _amplitude.add(rms);

  /// Test helper: simulate the engine's silence policy firing auto-submit.
  void fireAutoSubmit() => autoSubmit?.call();

  @override
  Stream<String> get partials => _partials.stream;

  @override
  Stream<double> get amplitude => _amplitude.stream;

  @override
  Future<SttResult> stop() async {
    started = false;
    return SttResult(transcript: nextResultOk ? nextTranscript : '', ok: nextResultOk);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    if (!_partials.isClosed) await _partials.close();
    if (!_amplitude.isClosed) await _amplitude.close();
  }
}
