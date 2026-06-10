import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'silence_detector.dart';
import 'stt_engine.dart';

const _kSampleRate = 16000;

/// Cloud [SttEngine]: owns a `record` PCM16 mic stream, buffers the audio in
/// memory (capped at [maxBufferSeconds] so it stays under Google sync
/// recognize's ~60 s / 10 MB inline limit), and transcribes the whole utterance
/// on [stop] via the injected [transcribe] callback (wired to the backend
/// proxy). [partials] is empty — cloud is batch, no interim text. A
/// [SilenceDetector] drives auto-submit exactly as the on-device engine does.
class CloudSttEngine implements SttEngine {
  CloudSttEngine({
    required this.silenceSeconds,
    required this.transcribe,
    this.maxBufferSeconds = 60,
  });

  final double silenceSeconds;
  final int maxBufferSeconds;

  /// Posts headerless LINEAR16 PCM and returns the transcript (throws on error).
  final Future<String> Function(Uint8List pcm, int sampleRate) transcribe;

  // Created lazily in start() — the AudioRecorder constructor touches native
  // `record`, so deferring it keeps the buffer/transcribe logic unit-testable.
  AudioRecorder? _recorder;
  final _partials = StreamController<String>.broadcast();
  final _amplitude = StreamController<double>.broadcast();
  final _buffer = BytesBuilder(copy: false);
  SilenceDetector? _silence;
  StreamSubscription? _micSub;
  void Function()? _onAutoSubmit;
  bool _capped = false;
  int get _maxBytes => maxBufferSeconds * _kSampleRate * 2;

  @override
  Stream<String> get partials => _partials.stream;

  @override
  Stream<double> get amplitude => _amplitude.stream;

  @override
  Future<void> start({void Function()? onAutoSubmit}) async {
    _arm(onAutoSubmit);
    final recorder = _recorder ??= AudioRecorder();
    final mic = await recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: 1,
      androidConfig:
          AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
    ));
    _micSub = mic.listen(_ingest);
  }

  void _arm(void Function()? onAutoSubmit) {
    _onAutoSubmit = onAutoSubmit;
    _silence = onAutoSubmit == null
        ? null
        : SilenceDetector(
            sampleRate: _kSampleRate, silenceSeconds: silenceSeconds);
  }

  /// Test seam: arm the auto-submit/silence policy without starting `record`.
  @visibleForTesting
  void armForTest({void Function()? onAutoSubmit}) => _arm(onAutoSubmit);

  /// Test seam: feed PCM as if from the mic, without `record`.
  @visibleForTesting
  void ingestForTest(Uint8List bytes) => _ingest(bytes);

  void _ingest(Uint8List bytes) {
    if (_capped) return;
    if (_buffer.length + bytes.length >= _maxBytes) {
      // Take up to the cap, then flush via auto-submit.
      final room = _maxBytes - _buffer.length;
      if (room > 0) _buffer.add(Uint8List.sublistView(bytes, 0, room));
      _capped = true;
      _onAutoSubmit?.call();
      return;
    }
    _buffer.add(bytes);
    final floats = _pcm16ToFloat32(bytes);
    // Raw linear RMS for the prism visualiser (shader owns gate + smoothing).
    // Guard: a mic callback can land after dispose() closes the controller.
    if (!_amplitude.isClosed) _amplitude.add(_rms(floats));
    final silence = _silence;
    if (silence != null && silence.addPcm(floats)) {
      _capped = true; // stop feeding the detector after it fires
      _onAutoSubmit?.call();
    }
  }

  @override
  Future<SttResult> stop() async {
    await _micSub?.cancel();
    _micSub = null;
    final recorder = _recorder;
    if (recorder != null) {
      try {
        if (await recorder.isRecording()) await recorder.stop();
      } catch (_) {}
    }
    final pcm = _buffer.toBytes();
    if (pcm.isEmpty) return const SttResult(transcript: '');
    try {
      final text = await transcribe(pcm, _kSampleRate);
      return SttResult(transcript: text.trim());
    } catch (e) {
      return SttResult(transcript: '', ok: false, error: '$e');
    }
  }

  @override
  Future<void> dispose() async {
    await _micSub?.cancel();
    _micSub = null;
    if (!_partials.isClosed) await _partials.close();
    if (!_amplitude.isClosed) await _amplitude.close();
    _recorder?.dispose();
  }

  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  static double _rms(Float32List s) {
    if (s.isEmpty) return 0.0;
    var sum = 0.0;
    for (final v in s) {
      sum += v * v;
    }
    return math.sqrt(sum / s.length);
  }
}
