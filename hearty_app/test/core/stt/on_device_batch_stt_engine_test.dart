import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/on_device_batch_stt_engine.dart';

Uint8List _pcmBytes(int samples) => Uint8List(samples * 2); // 16-bit silence

/// 16-bit PCM at a constant amplitude (rms == |amp|, like the detector tests).
Uint8List _pcmTone(int samples, double amp) {
  final bd = ByteData(samples * 2);
  final v = (amp * 32767).round().clamp(-32768, 32767);
  for (var i = 0; i < samples; i++) {
    bd.setInt16(i * 2, v, Endian.little);
  }
  return bd.buffer.asUint8List();
}

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

    test('emits per-chunk RMS on the amplitude stream (#13 prism)', () async {
      final engine = OnDeviceBatchSttEngine(
        silenceSeconds: 2.5,
        decode: (_) async => '',
      );
      final seen = <double>[];
      final sub = engine.amplitude.listen(seen.add);
      engine.ingestForTest(_pcmBytes(1600)); // silence -> rms 0
      engine.ingestForTest(_pcmTone(1600, 0.25)); // tone -> rms ~0.25
      await Future<void>.delayed(Duration.zero); // let the broadcast deliver
      expect(seen.length, 2);
      expect(seen[0], closeTo(0.0, 1e-6));
      expect(seen[1], closeTo(0.25, 0.01));
      await sub.cancel();
    });

    test('amplitude stream closes on dispose without throwing', () async {
      final engine = OnDeviceBatchSttEngine(
        silenceSeconds: 2.5,
        decode: (_) async => '',
      );
      var closed = false;
      engine.amplitude.listen(null, onDone: () => closed = true);
      await engine.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(closed, isTrue);
      // A late mic callback after dispose must not throw (guarded by isClosed).
      engine.ingestForTest(_pcmTone(160, 0.2));
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

    test('a hung decode times out to ok:false (warm isolate died)', () async {
      final engine = OnDeviceBatchSttEngine(
        silenceSeconds: 2.5,
        decodeTimeout: const Duration(milliseconds: 50),
        decode: (samples) => Completer<String>().future, // never completes
      );
      engine.ingestForTest(_pcmBytes(1600));
      final result = await engine.stop();
      expect(result.ok, isFalse);
      expect(result.transcript, isEmpty);
    });

    test('auto-submit fires for a quiet speaker (adaptive VAD)', () async {
      var autoSubmits = 0;
      final engine = OnDeviceBatchSttEngine(
        silenceSeconds: 2.5,
        decode: (samples) async => '',
      );
      engine.armForTest(onAutoSubmit: () => autoSubmits++);
      // Quiet speech, amp 0.01 — below the old fixed 0.015 cut.
      for (var i = 0; i < 5; i++) {
        engine.ingestForTest(_pcmTone(1600, 0.01));
      }
      for (var i = 0; i < 24; i++) {
        engine.ingestForTest(_pcmBytes(1600)); // 2.4s silence — not yet
      }
      expect(autoSubmits, 0);
      engine.ingestForTest(_pcmBytes(1600)); // crosses 2.5s — fires
      expect(autoSubmits, 1);
    });
  });
}
