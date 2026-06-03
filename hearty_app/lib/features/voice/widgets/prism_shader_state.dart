import 'dart:math' as math;

/// Spatial frequency — how many wave humps fit across the screen (~4 humps).
/// Decoupled from [kChroma] so the snaky wave stays clean (spec §2–3).
const double kWaveFreq = 13.0;

/// Max chromatic phase separation between R/G/B channels (spec §3).
const double kChroma = 2.6;

/// Vertical wave offset (as a fraction of `minDim/2`) for one RGB channel at
/// horizontal pixel [px]. Ported verbatim from the prototype's `drawShader`
/// inner loop. The painter places the point at `cy + return * (minDim / 2)`.
///
/// The centre-weighted `spread = sin²(πx/W)` is 0 at both edges and 1 at the
/// centre, so the chromatic term vanishes at the sides (all channels coincide
/// → white) and peaks mid-screen — this is what pins the prism split to the
/// centre. With [distortion] and [norm] both 0 the channels coincide
/// everywhere, giving the calm single beam.
double prismChannelOffset({
  required double px,
  required double width,
  required double height,
  required int channelSign,
  required double time,
  required double yScale,
  required double distortion,
  required double norm,
}) {
  final sp = math.sin((px / width) * math.pi);
  final spread = sp * sp;
  final nx = (px * 2 - width) / math.min(width, height);
  final phase = nx * kWaveFreq + time + channelSign * spread * distortion * kChroma;
  return math.sin(phase) * yScale +
      math.sin(phase * 2.1 + 1.3) * yScale * 0.38 * (norm * norm);
}

/// Per-frame audio→visual driver for the prism waveform.
///
/// A faithful port of the reference prototype's `loop()` (see
/// `docs/superpowers/specs/2026-06-01-prism-waveform-voice-visualizer.md`,
/// §4–5). It owns the two-stage smoothing and the absolute noise gate, and
/// exposes the four shader parameters the painter consumes.
///
/// [tick] is called once per rendered frame with the latest raw RMS sample,
/// already normalised into the linear 0..1 domain the constants assume (see
/// the platform mapping in `prism_waveform.dart`). The audio callback rate is
/// lower than the frame rate, so the most-recent sample is simply re-fed on
/// frames with no new audio — identical in behaviour to the prototype, where
/// the analyser returns near-identical values across adjacent frames.
///
/// All constants are the spec §3 values, kept as mutable fields so they stay
/// tunable per device (spec §4 sanctions retuning [gateMargin]/[speechSpan]).
class PrismShaderState {
  // ── Audio stage (§3 "Audio → visual mapping", §4 gate) ──
  /// Fast attack so speech onset registers within a frame or two.
  double attackAlpha = 0.45;

  /// Slower release so the wave does not collapse between syllables.
  double releaseAlpha = 0.12;

  /// RMS must exceed `noiseFloor + gateMargin` before any split appears.
  double gateMargin = 0.012;

  /// RMS range above the gate that maps to the full prism.
  double speechSpan = 0.16;

  /// Slight low-end boost so normal speech reaches a good split.
  double normExponent = 0.75;

  /// Adaptive-floor clamp + slow rise rate (it drops instantly to any new
  /// quiet minimum, rises only very slowly to learn the mic hiss).
  double floorMin = 0.002;
  double floorMax = 0.06;
  double floorRise = 0.002;

  // ── Visual stage (§5 two-stage smoothing) ──
  double distLerp = 0.35;
  double scaleLerp = 0.30;
  double normLerp = 0.30;

  // ── Visual target shaping (§3) ──
  double distortionPeak = 0.36;
  double yScaleCalm = 0.05;
  double yScaleGain = 0.50;
  double timeBase = 0.01;
  double timeGain = 0.10;

  // ── State ──
  double _smoothRms = 0.0;
  double _noiseFloor = 0.02; // adaptive — tracks the quietest recent level
  double _visDistort = 0.0;
  double _visYScale = 0.05;
  double _visNorm = 0.0;
  double _time = 0.0;

  /// Horizontal scroll phase (radians).
  double get time => _time;

  /// Visually-smoothed chromatic split amount (0 = white beam).
  double get distortion => _visDistort;

  /// Visually-smoothed wave amplitude (`yScaleCalm` at silence).
  double get yScale => _visYScale;

  /// Visually-smoothed split/harmonic/speed driver, 0..1.
  double get norm => _visNorm;

  /// Advances one frame given the latest raw RMS sample (linear 0..1).
  void tick(double rawRms) {
    // Stage 1 — smooth the raw RMS (fast attack, slower release).
    final alpha = rawRms > _smoothRms ? attackAlpha : releaseAlpha;
    _smoothRms = _smoothRms * (1 - alpha) + rawRms * alpha;

    // Adaptive noise floor: drop instantly to any new quiet minimum, rise
    // only very slowly. Learns the device's mic hiss without ever letting it
    // register as speech.
    if (_smoothRms < _noiseFloor) {
      _noiseFloor = _smoothRms;
    } else {
      _noiseFloor += (_smoothRms - _noiseFloor) * floorRise;
    }
    _noiseFloor = _noiseFloor.clamp(floorMin, floorMax);

    // Absolute gate: only RMS above (floor + margin) produces signal. Below →
    // exactly 0, so silence shows the calm single beam with no prism.
    final gate = _noiseFloor + gateMargin;
    final above = _smoothRms - gate;
    final norm = above <= 0
        ? 0.0
        : math.min(math.pow(above / speechSpan, normExponent).toDouble(), 1.0);

    // Stage 2 — visual lerp on shader params (prevents loud spikes snapping).
    final targetDistort = norm * distortionPeak;
    final targetYScale = yScaleCalm + norm * yScaleGain;
    _visDistort += (targetDistort - _visDistort) * distLerp;
    _visYScale += (targetYScale - _visYScale) * scaleLerp;
    _visNorm += (norm - _visNorm) * normLerp;

    // Scroll speed: slow calm drift at silence, lively flow when loud.
    _time += timeBase + _visNorm * timeGain;
  }
}
