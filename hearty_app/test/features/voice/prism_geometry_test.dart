import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/voice/widgets/prism_shader_state.dart';

void main() {
  // The three RGB channel signs from the spec (+1 red, 0 green, -1 blue).
  const red = 1, green = 0, blue = -1;
  const w = 400.0, h = 800.0; // a portrait canvas like the dictation screen

  double sample(int sign, double px,
          {double time = 0.7,
          double yScale = 0.3,
          double distortion = 0.3,
          double norm = 0.6}) =>
      prismChannelOffset(
        px: px,
        width: w,
        height: h,
        channelSign: sign,
        time: time,
        yScale: yScale,
        distortion: distortion,
        norm: norm,
      );

  group('prismChannelOffset', () {
    test('the three channels coincide at the left edge (white)', () {
      // spread = sin(0) = 0 → chromatic term vanishes → all channels equal.
      expect(sample(red, 0), closeTo(sample(green, 0), 1e-12));
      expect(sample(blue, 0), closeTo(sample(green, 0), 1e-12));
    });

    test('the three channels coincide at the right edge (white)', () {
      // spread = sin(π) = 0 at px == width.
      expect(sample(red, w), closeTo(sample(green, w), 1e-12));
      expect(sample(blue, w), closeTo(sample(green, w), 1e-12));
    });

    test('in silence the channels coincide everywhere (single beam)', () {
      for (final px in [0.0, 80.0, 200.0, 333.0, w]) {
        final g = sample(green, px, distortion: 0, norm: 0);
        expect(sample(red, px, distortion: 0, norm: 0), closeTo(g, 1e-12),
            reason: 'no split anywhere when distortion is 0');
        expect(sample(blue, px, distortion: 0, norm: 0), closeTo(g, 1e-12));
      }
    });

    test('the channels diverge at the centre when speaking', () {
      // spread peaks at the centre, so the prism split is strongest there.
      final r = sample(red, w / 2);
      final b = sample(blue, w / 2);
      expect((r - b).abs(), greaterThan(0.05),
          reason: 'red and blue separate in the middle');
    });

    test('the split is wider at the centre than near the edge', () {
      double spreadAt(double px) =>
          (sample(red, px) - sample(blue, px)).abs();
      expect(spreadAt(w / 2), greaterThan(spreadAt(w * 0.06)),
          reason: 'centre-weighted spread pins white to the edges');
    });

    test('the calm beam amplitude stays small', () {
      // yScale 0.05, norm 0 → |wave| <= 0.05 (no second harmonic).
      for (final px in [0.0, 120.0, 250.0, w]) {
        expect(sample(green, px, yScale: 0.05, distortion: 0, norm: 0).abs(),
            lessThanOrEqualTo(0.05 + 1e-9));
      }
    });
  });
}
