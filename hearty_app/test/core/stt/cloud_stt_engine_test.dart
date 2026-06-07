import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/cloud_stt_engine.dart';

Uint8List _pcmBytes(int samples) => Uint8List(samples * 2); // silence, 16-bit

void main() {
  group('CloudSttEngine', () {
    test('buffers fed PCM and transcribes it on stop', () async {
      Uint8List? sent;
      final engine = CloudSttEngine(
        silenceSeconds: 2.5,
        transcribe: (pcm, sr) async {
          sent = pcm;
          return 'i had a turkey sandwich';
        },
      );
      // ingestForTest mimics the mic callback without `record`.
      engine.ingestForTest(_pcmBytes(1600));
      engine.ingestForTest(_pcmBytes(1600));
      final result = await engine.stop();
      expect(result.ok, isTrue);
      expect(result.transcript, 'i had a turkey sandwich');
      expect(sent!.length, 1600 * 2 * 2); // both chunks buffered
    });

    test('caps the buffer at maxBufferSeconds and fires auto-submit', () async {
      var autoSubmits = 0;
      final engine = CloudSttEngine(
        silenceSeconds: 2.5,
        maxBufferSeconds: 1, // 1s = 16000 samples
        transcribe: (pcm, sr) async => '',
      );
      engine.armForTest(onAutoSubmit: () => autoSubmits++);
      engine.ingestForTest(_pcmBytes(16000)); // exactly the cap
      engine.ingestForTest(_pcmBytes(1600)); // overflow ignored
      expect(autoSubmits, 1);
      final result = await engine.stop();
      expect(result.ok, isTrue);
    });

    test('returns ok:false when transcribe throws (caller falls back)',
        () async {
      final engine = CloudSttEngine(
        silenceSeconds: 2.5,
        transcribe: (pcm, sr) async => throw StateError('network'),
      );
      engine.ingestForTest(_pcmBytes(1600));
      final result = await engine.stop();
      expect(result.ok, isFalse);
      expect(result.transcript, isEmpty);
    });

    test('empty buffer returns an empty transcript without calling transcribe',
        () async {
      var called = false;
      final engine = CloudSttEngine(
        silenceSeconds: 2.5,
        transcribe: (pcm, sr) async {
          called = true;
          return 'should not happen';
        },
      );
      final result = await engine.stop();
      expect(result.ok, isTrue);
      expect(result.transcript, isEmpty);
      expect(called, isFalse);
    });
  });
}
