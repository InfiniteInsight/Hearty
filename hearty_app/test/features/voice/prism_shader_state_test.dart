import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/voice/widgets/prism_shader_state.dart';

/// Advances [state] for [frames] frames, all fed the same raw RMS sample.
void _run(PrismShaderState state, double rawRms, int frames) {
  for (var i = 0; i < frames; i++) {
    state.tick(rawRms);
  }
}

void main() {
  group('PrismShaderState', () {
    test('initial state is the calm white beam', () {
      final s = PrismShaderState();
      expect(s.norm, 0.0);
      expect(s.distortion, 0.0);
      expect(s.yScale, closeTo(0.05, 1e-9)); // calm amplitude
      expect(s.time, 0.0);
    });

    test('sustained silence keeps the beam calm — no prism split', () {
      final s = PrismShaderState();
      _run(s, 0.0, 300);
      expect(s.norm, 0.0, reason: 'silence must hard-zero the split driver');
      expect(s.distortion, 0.0, reason: 'no chromatic split in silence');
      expect(s.yScale, closeTo(0.05, 1e-6), reason: 'amplitude stays calm');
    });

    test('sustained loud speech opens the prism', () {
      final s = PrismShaderState();
      _run(s, 0.5, 120);
      expect(s.norm, greaterThan(0.5));
      expect(s.distortion, greaterThan(0.2),
          reason: 'split eases toward the 0.36 peak target');
      expect(s.distortion, lessThanOrEqualTo(0.36 + 1e-9));
      expect(s.yScale, greaterThan(0.05),
          reason: 'wave grows taller than the calm baseline');
    });

    test('on-device normal speech opens the prism without shouting (#13 calib)',
        () {
      // Measured on a Pixel 4a (voiceRecognition source): silence/pauses floor
      // at ~0.002 and normal speech sits at ~0.02–0.05 RMS. Inter-word pauses
      // pin the adaptive floor low (it drops instantly to quiet minimums), so
      // warm with silence then feed a normal-speech burst — the prism must
      // clearly split, not sit flat as it did before the gate/span calibration.
      final s = PrismShaderState();
      _run(s, 0.002, 200); // quiet floor learns the AGC-suppressed silence
      _run(s, 0.03, 30); // a normal speaking level
      expect(s.norm, greaterThan(0.5),
          reason: 'normal ~0.03 RMS speech must drive a strong split');
      expect(s.distortion, greaterThan(0.2));
    });

    test('steady on-device ambient (mic hiss) never opens the prism', () {
      // The adaptive floor must learn the quiet level so constant ambient
      // stays below the gate (floor + margin) → no split. 0.005 is the measured
      // resting ambient on the Pixel 4a (voiceRecognition source, AGC), which
      // the gate must reject even after the gateMargin was tightened to 0.003
      // to register this speaker's quiet voiced speech.
      final s = PrismShaderState();
      _run(s, 0.005, 800);
      expect(s.norm, 0.0,
          reason: 'steady ambient is absorbed by the adaptive noise floor');
      expect(s.distortion, 0.0);
    });

    test('the wave scrolls faster when speaking than in silence', () {
      final calm = PrismShaderState();
      final t0Calm = calm.time;
      _run(calm, 0.0, 100);
      final calmAdvance = calm.time - t0Calm;

      final loud = PrismShaderState();
      _run(loud, 0.5, 100); // let the visual norm ramp up first
      final tLoud = loud.time;
      _run(loud, 0.5, 100);
      final loudAdvance = loud.time - tLoud;

      expect(calmAdvance, greaterThan(0.0), reason: 'calm still drifts');
      expect(loudAdvance, greaterThan(calmAdvance * 2),
          reason: 'loud speech scrolls markedly faster');
    });

    test('the split eases in over several frames rather than snapping', () {
      final s = PrismShaderState();
      // One loud frame from rest should not jump straight to the peak split.
      s.tick(0.5);
      expect(s.distortion, lessThan(0.36),
          reason: 'visual lerp prevents an instant snap to peak');
    });
  });
}
