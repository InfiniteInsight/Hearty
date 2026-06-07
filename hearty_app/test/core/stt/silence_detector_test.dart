import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/silence_detector.dart';

Float32List _tone(int samples, double amp) =>
    Float32List.fromList(List.filled(samples, amp));

void main() {
  group('SilenceDetector', () {
    test('does not fire on pre-speech silence', () {
      final d = SilenceDetector(sampleRate: 16000, silenceSeconds: 2.5);
      for (var i = 0; i < 50; i++) {
        expect(d.addPcm(_tone(1600, 0.0)), isFalse); // 0.1s chunks, 5s total
      }
    });

    test('fires after trailing silence once speech has occurred', () {
      final d = SilenceDetector(sampleRate: 16000, silenceSeconds: 2.5);
      expect(d.addPcm(_tone(1600, 0.3)), isFalse); // speech
      for (var i = 0; i < 24; i++) {
        expect(d.addPcm(_tone(1600, 0.0)), isFalse); // 2.4s silence — not yet
      }
      expect(d.addPcm(_tone(1600, 0.0)), isTrue); // crosses 2.5s — fires
    });

    test('resets trailing silence when speech resumes', () {
      final d = SilenceDetector(sampleRate: 16000, silenceSeconds: 2.5);
      d.addPcm(_tone(1600, 0.3));
      for (var i = 0; i < 20; i++) {
        d.addPcm(_tone(1600, 0.0)); // 2.0s silence
      }
      d.addPcm(_tone(1600, 0.3)); // speech again → reset
      for (var i = 0; i < 24; i++) {
        expect(d.addPcm(_tone(1600, 0.0)), isFalse); // 2.4s from reset
      }
      expect(d.addPcm(_tone(1600, 0.0)), isTrue); // 2.5s from reset
    });

    test('reset() clears state', () {
      final d = SilenceDetector(sampleRate: 16000, silenceSeconds: 2.5);
      d.addPcm(_tone(1600, 0.3));
      d.reset();
      for (var i = 0; i < 30; i++) {
        expect(d.addPcm(_tone(1600, 0.0)), isFalse); // pre-speech again
      }
    });
  });
}
