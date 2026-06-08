import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/pcm_utils.dart';

double _peak(Float32List s) {
  var p = 0.0;
  for (final v in s) {
    final a = v.abs();
    if (a > p) p = a;
  }
  return p;
}

void main() {
  group('pcm16ToFloat32', () {
    test('converts little-endian int16 to normalized doubles', () {
      // 0x0000=0, 0x4000=16384 → 0.5, 0x8000=-32768 → -1.0
      final bytes = Uint8List.fromList([0x00, 0x00, 0x00, 0x40, 0x00, 0x80]);
      final out = pcm16ToFloat32(bytes);
      expect(out.length, 3);
      expect(out[0], 0.0);
      expect(out[1], closeTo(0.5, 1e-4));
      expect(out[2], closeTo(-1.0, 1e-4));
    });
  });

  group('normalizeAndPad', () {
    test('boosts a quiet clip so its peak reaches ~0.95', () {
      final quiet = Float32List.fromList(List.filled(16000, 0.03));
      final out = normalizeAndPad(quiet);
      expect(_peak(out), closeTo(0.95, 1e-3));
    });

    test('normalizes a near-full-scale clip down to ~0.95 too', () {
      final loud = Float32List.fromList(List.filled(16000, 1.0));
      expect(_peak(normalizeAndPad(loud)), closeTo(0.95, 1e-3));
    });

    test('pads short input to at least 1.5s with leading silence', () {
      final short = Float32List.fromList(List.filled(1600, 0.5)); // 0.1s
      final out = normalizeAndPad(short);
      expect(out.length, 24000); // 1.5s @ 16kHz
      // first 0.1s (1600 samples) is leading silence
      for (var i = 0; i < 1600; i++) {
        expect(out[i], 0.0);
      }
      expect(out[1600], greaterThan(0.0)); // speech starts after the lead
    });

    test('keeps lead+body+lead when already longer than the minimum', () {
      final long = Float32List.fromList(List.filled(32000, 0.5)); // 2s
      final out = normalizeAndPad(long);
      expect(out.length, 1600 + 32000 + 1600);
    });

    test('all-silence input stays silent (no divide-by-zero)', () {
      final silence = Float32List(16000);
      final out = normalizeAndPad(silence);
      expect(_peak(out), 0.0);
    });
  });
}
