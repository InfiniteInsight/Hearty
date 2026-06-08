import 'dart:typed_data';

/// Convert headerless little-endian PCM16 [bytes] to Float32 samples in -1..1.
Float32List pcm16ToFloat32(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final n = bytes.length ~/ 2;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Peak-normalize [s] to [targetPeak] (SNR-preserving gain) and pad with
/// [leadMs] of leading + trailing silence to at least [minMs] total. Fixes the
/// quiet/short-clip blanks the on-device spike found (especially Moonshine,
/// which returns no tokens on very quiet or sub-second audio). All-silence input
/// is returned silent (no divide-by-zero).
Float32List normalizeAndPad(
  Float32List s, {
  double targetPeak = 0.95,
  int sampleRate = 16000,
  int leadMs = 100,
  int minMs = 1500,
}) {
  var peak = 0.0;
  for (final v in s) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  final gain = peak > 1e-4 ? targetPeak / peak : 1.0;
  final lead = leadMs * sampleRate ~/ 1000;
  final minLen = minMs * sampleRate ~/ 1000;
  final padded = lead * 2 + s.length;
  final total = padded < minLen ? minLen : padded;
  final out = Float32List(total);
  for (var i = 0; i < s.length; i++) {
    out[lead + i] = s[i] * gain;
  }
  return out;
}
