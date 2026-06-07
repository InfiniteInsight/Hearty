import 'dart:math' as math;
import 'dart:typed_data';

/// Decides when a turn should auto-submit: fires once trailing silence (after
/// speech has started) reaches [silenceSeconds]. Deterministic — duration is
/// derived from sample counts, not wall-clock, so it is unit-testable and
/// engine-agnostic (the same detector works for any PCM source).
class SilenceDetector {
  SilenceDetector({
    required this.sampleRate,
    required this.silenceSeconds,
    this.rmsThreshold = 0.015,
  });

  final int sampleRate;
  final double silenceSeconds;
  final double rmsThreshold;

  bool _spoke = false;
  double _trailingSilence = 0;

  /// Feed a PCM chunk (Float32, -1..1). Returns true exactly when the turn
  /// should auto-submit. After it returns true the caller should stop feeding.
  bool addPcm(Float32List samples) {
    if (samples.isEmpty) return false;
    final seconds = samples.length / sampleRate;
    if (_rms(samples) >= rmsThreshold) {
      _spoke = true;
      _trailingSilence = 0;
      return false;
    }
    if (!_spoke) return false; // ignore pre-speech silence
    _trailingSilence += seconds;
    return _trailingSilence >= silenceSeconds;
  }

  void reset() {
    _spoke = false;
    _trailingSilence = 0;
  }

  static double _rms(Float32List s) {
    var sum = 0.0;
    for (final v in s) {
      sum += v * v;
    }
    return math.sqrt(sum / s.length);
  }
}
