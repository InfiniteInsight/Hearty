import 'dart:async';
import 'package:hearty_app/core/stt/stt_engine.dart';

/// Test double for [SttEngine]. Lets tests drive partials, simulate the
/// engine's silence policy firing, and control the final transcript.
class FakeSttEngine implements SttEngine {
  final _partials = StreamController<String>.broadcast();
  String nextTranscript = '';
  bool started = false;
  int startCount = 0;
  int disposeCount = 0;
  void Function()? autoSubmit;

  @override
  Future<void> start({void Function()? onAutoSubmit}) async {
    started = true;
    startCount++;
    autoSubmit = onAutoSubmit;
  }

  /// Test helper: push a live partial.
  void emitPartial(String text) => _partials.add(text);

  /// Test helper: simulate the engine's silence policy firing auto-submit.
  void fireAutoSubmit() => autoSubmit?.call();

  @override
  Stream<String> get partials => _partials.stream;

  @override
  Future<SttResult> stop() async {
    started = false;
    return SttResult(transcript: nextTranscript);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    if (!_partials.isClosed) await _partials.close();
  }
}
