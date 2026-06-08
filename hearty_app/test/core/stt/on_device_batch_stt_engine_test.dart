import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/on_device_batch_stt_engine.dart';

Uint8List _pcmBytes(int samples) => Uint8List(samples * 2); // 16-bit silence

void main() {
  group('OnDeviceBatchSttEngine', () {
    test('buffers fed PCM, normalize+pads it, and decodes on stop', () async {
      Float32List? decoded;
      final engine = OnDeviceBatchSttEngine(
        silenceSeconds: 2.5,
        decode: (samples) async {
          decoded = samples;
          return 'i had bloating';
        },
      );
      engine.ingestForTest(_pcmBytes(1600));
      engine.ingestForTest(_pcmBytes(1600));
      final result = await engine.stop();
      expect(result.ok, isTrue);
      expect(result.transcript, 'i had bloating');
      // normalize+pad enforces a >=1.5s (24000-sample) minimum
      expect(decoded!.length, greaterThanOrEqualTo(24000));
    });

    test('caps the buffer at maxBufferSeconds and fires auto-submit', () async {
      var autoSubmits = 0;
      final engine = OnDeviceBatchSttEngine(
        silenceSeconds: 2.5,
        maxBufferSeconds: 1, // 1s = 16000 samples
        decode: (samples) async => '',
      );
      engine.armForTest(onAutoSubmit: () => autoSubmits++);
      engine.ingestForTest(_pcmBytes(16000));
      engine.ingestForTest(_pcmBytes(1600)); // overflow ignored
      expect(autoSubmits, 1);
    });

    test('empty buffer returns empty without calling decode', () async {
      var called = false;
      final engine = OnDeviceBatchSttEngine(
        silenceSeconds: 2.5,
        decode: (samples) async {
          called = true;
          return 'nope';
        },
      );
      final result = await engine.stop();
      expect(result.ok, isTrue);
      expect(result.transcript, isEmpty);
      expect(called, isFalse);
    });

    test('decode failure surfaces ok:false (caller falls back to manual)',
        () async {
      final engine = OnDeviceBatchSttEngine(
        silenceSeconds: 2.5,
        decode: (samples) async => throw StateError('isolate died'),
      );
      engine.ingestForTest(_pcmBytes(1600));
      final result = await engine.stop();
      expect(result.ok, isFalse);
      expect(result.transcript, isEmpty);
    });
  });
}
