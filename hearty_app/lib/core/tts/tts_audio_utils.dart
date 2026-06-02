// lib/core/tts/tts_audio_utils.dart
//
// PERMANENT helpers reused by Phase 1 TTS integration.
// Do NOT delete when removing the spike screen.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Copies every file under [assetDir] (e.g.
/// `assets/tts/hearty-neutral`) out of the Flutter asset
/// bundle into a stable location under the app documents directory, preserving
/// subdirectory structure (including nested espeak-ng-data trees).
///
/// Returns the on-disk path to the copied model directory.
///
/// Idempotent: if the main `.onnx` model file already exists the copy is
/// skipped and the cached directory path is returned immediately.
Future<String> copyModelAssets(String assetDir) async {
  final docsDir = await getApplicationDocumentsDirectory();
  // Strip trailing slash for consistent path joins.
  final cleanAssetDir =
      assetDir.endsWith('/') ? assetDir.substring(0, assetDir.length - 1) : assetDir;
  final destDir = '${docsDir.path}/$cleanAssetDir';

  // Skip-if-present check: the caller knows the model filename
  // (e.g. "hearty-neutral.onnx"); here we just check whether ANY .onnx file
  // already exists in the destination to decide if the copy can be skipped.
  final destDirRef = Directory(destDir);
  if (destDirRef.existsSync()) {
    final onnxExists = destDirRef
        .listSync(recursive: true)
        .any((e) => e is File && e.path.endsWith('.onnx'));
    if (onnxExists) {
      return destDir;
    }
  }

  // Enumerate all bundled assets using the binary manifest (preferred over
  // legacy AssetManifest.json which may not be generated on modern SDKs).
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final allKeys = manifest.listAssets();

  // Filter to keys that belong to this asset directory.
  final prefix = cleanAssetDir.endsWith('/') ? cleanAssetDir : '$cleanAssetDir/';
  final keys = allKeys.where((k) => k.startsWith(prefix)).toList();
  if (keys.isEmpty) {
    debugPrint('copyModelAssets: no assets found under $prefix');
  }

  for (final key in keys) {
    // Derive the destination path by replacing the asset prefix with the
    // documents-directory prefix.
    final relative = key.substring(cleanAssetDir.length); // e.g. /tokens.txt
    final destPath = '$destDir$relative';

    final destFile = File(destPath);
    // Create parent directories (handles nested espeak-ng-data/* paths).
    await destFile.parent.create(recursive: true);

    // Use load() (not loadString()) to safely handle binary files like .onnx.
    final byteData = await rootBundle.load(key);
    await destFile.writeAsBytes(
      byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      flush: true,
    );
  }

  return destDir;
}

/// Wraps [samples] (Float32 PCM, range ~-1.0 to 1.0) as a standard 16-bit
/// mono PCM WAV byte buffer with a correct 44-byte RIFF/WAVE header.
///
/// Header layout (all multi-byte numerics little-endian):
/// Offset  Size  Field
///  0       4    "RIFF"
///  4       4    ChunkSize = 36 + dataLen
///  8       4    "WAVE"
/// 12       4    "fmt "
/// 16       4    Subchunk1Size = 16
/// 20       2    AudioFormat = 1 (PCM)
/// 22       2    NumChannels = 1
/// 24       4    SampleRate
/// 28       4    ByteRate = SampleRate * 2
/// 32       2    BlockAlign = 2
/// 34       2    BitsPerSample = 16
/// 36       4    "data"
/// 40       4    Subchunk2Size = dataLen (= samples.length * 2)
/// 44       N    Sample data (little-endian int16)
Uint8List pcmToWav(Float32List samples, int sampleRate) {
  final dataLen = samples.length * 2; // 2 bytes per int16 sample
  final totalLen = 44 + dataLen;
  final buf = ByteData(totalLen);

  // RIFF chunk descriptor
  _writeAscii(buf, 0, 'RIFF');
  buf.setUint32(4, 36 + dataLen, Endian.little); // ChunkSize
  _writeAscii(buf, 8, 'WAVE');

  // "fmt " sub-chunk
  _writeAscii(buf, 12, 'fmt ');
  buf.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM = 16)
  buf.setUint16(20, 1, Endian.little);  // AudioFormat: 1 = PCM
  buf.setUint16(22, 1, Endian.little);  // NumChannels: 1 (mono)
  buf.setUint32(24, sampleRate, Endian.little); // SampleRate
  buf.setUint32(28, sampleRate * 2, Endian.little); // ByteRate = SR * 1ch * 2B
  buf.setUint16(32, 2, Endian.little);  // BlockAlign = 1ch * 2B
  buf.setUint16(34, 16, Endian.little); // BitsPerSample

  // "data" sub-chunk
  _writeAscii(buf, 36, 'data');
  buf.setUint32(40, dataLen, Endian.little); // Subchunk2Size

  // Sample data: clamp → scale → int16 (little-endian)
  int offset = 44;
  for (final s in samples) {
    final clamped = s.clamp(-1.0, 1.0);
    final pcm16 = (clamped * 32767).round();
    buf.setInt16(offset, pcm16, Endian.little);
    offset += 2;
  }

  return buf.buffer.asUint8List();
}

/// Writes a 4-character ASCII [tag] into [buf] at [offset].
void _writeAscii(ByteData buf, int offset, String tag) {
  for (int i = 0; i < tag.length; i++) {
    buf.setUint8(offset + i, tag.codeUnitAt(i));
  }
}
