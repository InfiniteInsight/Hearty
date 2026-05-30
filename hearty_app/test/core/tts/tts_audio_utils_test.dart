// test/core/tts/tts_audio_utils_test.dart
//
// Pure-Dart unit tests for pcmToWav in tts_audio_utils.dart.
// These run without a device and verify the WAV header is correct.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/tts/tts_audio_utils.dart';

void main() {
  group('pcmToWav', () {
    test('output starts with ASCII "RIFF" and "WAVE"', () {
      final wav = pcmToWav(Float32List(0), 22050);
      expect(wav.length, 44, reason: 'zero samples → exactly 44 header bytes');

      // Bytes 0..3 == "RIFF"
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      // Bytes 8..11 == "WAVE"
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      // Bytes 12..15 == "fmt "
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      // Bytes 36..39 == "data"
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    });

    test('total byte length == 44 + samples.length * 2', () {
      const sampleCount = 100;
      final samples = Float32List(sampleCount);
      final wav = pcmToWav(samples, 22050);
      expect(wav.length, 44 + sampleCount * 2);
    });

    test('ChunkSize field == 36 + dataLen', () {
      const sampleCount = 50;
      final wav = pcmToWav(Float32List(sampleCount), 16000);
      final bd = ByteData.sublistView(wav);
      final chunkSize = bd.getUint32(4, Endian.little);
      expect(chunkSize, 36 + sampleCount * 2);
    });

    test('Subchunk2Size (data length) field == samples.length * 2', () {
      const sampleCount = 60;
      final wav = pcmToWav(Float32List(sampleCount), 22050);
      final bd = ByteData.sublistView(wav);
      final dataLen = bd.getUint32(40, Endian.little);
      expect(dataLen, sampleCount * 2);
    });

    test('AudioFormat == 1 (PCM), NumChannels == 1, BitsPerSample == 16', () {
      final wav = pcmToWav(Float32List(0), 22050);
      final bd = ByteData.sublistView(wav);
      expect(bd.getUint16(20, Endian.little), 1,  reason: 'AudioFormat PCM');
      expect(bd.getUint16(22, Endian.little), 1,  reason: 'NumChannels mono');
      expect(bd.getUint16(34, Endian.little), 16, reason: 'BitsPerSample');
    });

    test('SampleRate and ByteRate fields are set correctly', () {
      const sr = 22050;
      final wav = pcmToWav(Float32List(0), sr);
      final bd = ByteData.sublistView(wav);
      expect(bd.getUint32(24, Endian.little), sr,      reason: 'SampleRate');
      expect(bd.getUint32(28, Endian.little), sr * 2,  reason: 'ByteRate');
      expect(bd.getUint16(32, Endian.little), 2,        reason: 'BlockAlign');
    });

    test('sample data: +1.0 clamps to 32767, -1.0 clamps to -32767', () {
      final samples = Float32List.fromList([1.0, -1.0, 0.0]);
      final wav = pcmToWav(samples, 22050);
      final bd = ByteData.sublistView(wav);
      expect(bd.getInt16(44, Endian.little), 32767);
      expect(bd.getInt16(46, Endian.little), -32767);
      expect(bd.getInt16(48, Endian.little), 0);
    });

    test('sample data: out-of-range values are clamped', () {
      final samples = Float32List.fromList([2.0, -2.0]);
      final wav = pcmToWav(samples, 22050);
      final bd = ByteData.sublistView(wav);
      expect(bd.getInt16(44, Endian.little), 32767,  reason: 'clamp +2.0 → 32767');
      expect(bd.getInt16(46, Endian.little), -32767, reason: 'clamp -2.0 → -32767');
    });
  });
}
