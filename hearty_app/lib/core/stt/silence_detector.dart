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
    this.relativeThreshold,
    this.minThreshold = 0.003,
  });

  final int sampleRate;
  final double silenceSeconds;

  /// Absolute speech/silence cut used when [relativeThreshold] is null.
  final double rmsThreshold;

  /// When non-null, the speech cut adapts to the loudest chunk seen so far:
  /// `max(minThreshold, runningPeakRms * relativeThreshold)`. This is what the
  /// on-device batch engine uses — a quiet speaker's raw mic level sits below
  /// the fixed 0.015 cut, so the fixed detector never flips `_spoke` and
  /// auto-submit would never fire (it would wait out the 60 s buffer cap). The
  /// relative cut keys off the speaker's own peak, so trailing room-tone still
  /// reads as silence regardless of how quiet they are.
  final double? relativeThreshold;

  /// Floor for the adaptive cut so pure-silence noise drift can't masquerade as
  /// speech before any real speech has set the running peak.
  final double minThreshold;

  bool _spoke = false;
  double _trailingSilence = 0;
  double _peakRms = 0;

  /// Feed a PCM chunk (Float32, -1..1). Returns true exactly when the turn
  /// should auto-submit. After it returns true the caller should stop feeding.
  bool addPcm(Float32List samples) {
    if (samples.isEmpty) return false;
    final seconds = samples.length / sampleRate;
    final rms = _rms(samples);
    final double threshold;
    if (relativeThreshold == null) {
      threshold = rmsThreshold;
    } else {
      if (rms > _peakRms) _peakRms = rms;
      threshold = math.max(minThreshold, _peakRms * relativeThreshold!);
    }
    if (rms >= threshold) {
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
    _peakRms = 0;
  }

  static double _rms(Float32List s) {
    var sum = 0.0;
    for (final v in s) {
      sum += v * v;
    }
    return math.sqrt(sum / s.length);
  }
}
