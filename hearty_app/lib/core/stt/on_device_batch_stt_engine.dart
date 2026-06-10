import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'pcm_utils.dart';
import 'silence_detector.dart';
import 'stt_engine.dart';

const _kSampleRate = 16000;

/// On-device batch [SttEngine]: owns a `record` PCM16 mic, buffers the audio
/// (capped at [maxBufferSeconds]), and on [stop] normalize+pads it and decodes
/// the whole utterance via the injected [decode] callback — which is wired to a
/// **kept-warm** [BatchAsrIsolate] owned by `AsrModelManager` (so the engine
/// neither loads nor disposes the recognizer; keep-warm survives across
/// sessions). `partials` is empty (batch). A [SilenceDetector] drives auto-submit
/// exactly as the streaming/cloud engines do.
class OnDeviceBatchSttEngine implements SttEngine {
  OnDeviceBatchSttEngine({
    required this.silenceSeconds,
    required this.decode,
    this.maxBufferSeconds = 60,
    this.decodeTimeout = const Duration(seconds: 8),
  });

  final double silenceSeconds;
  final int maxBufferSeconds;

  /// Cap on a single decode; if the warm isolate dies no result returns, so we
  /// surface ok:false instead of wedging. Injectable so tests don't wait it out.
  final Duration decodeTimeout;

  /// Decode a whole utterance to text (throws on failure). Supplied by the
  /// model manager from its warm isolate; the engine does not own it.
  final Future<String> Function(Float32List samples) decode;

  AudioRecorder? _recorder; // lazy: constructor touches native record
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
            sampleRate: _kSampleRate,
            silenceSeconds: silenceSeconds,
            // Adaptive cut: the mic stream is raw (normalize+pad only runs at
            // stop()), so a quiet speaker sits below the fixed 0.015 cut and
            // auto-submit would never fire. Key the cut off their own peak.
            relativeThreshold: 0.35,
          );
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
      final room = _maxBytes - _buffer.length;
      if (room > 0) _buffer.add(Uint8List.sublistView(bytes, 0, room));
      _capped = true;
      _onAutoSubmit?.call();
      return;
    }
    _buffer.add(bytes);
    final floats = pcm16ToFloat32(bytes);
    // Surface per-chunk RMS for the prism visualiser. Raw linear RMS — the
    // shader (PrismShaderState) owns the noise gate + smoothing, so we don't
    // pre-scale. Guard: an in-flight mic callback can land after dispose().
    if (!_amplitude.isClosed) _amplitude.add(_rms(floats));
    final silence = _silence;
    if (silence != null && silence.addPcm(floats)) {
      _capped = true;
      _onAutoSubmit?.call();
    }
  }

  static double _rms(Float32List s) {
    if (s.isEmpty) return 0.0;
    var sum = 0.0;
    for (final v in s) {
      sum += v * v;
    }
    return math.sqrt(sum / s.length);
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
    final samples = normalizeAndPad(pcm16ToFloat32(pcm));
    try {
      // Bound the decode: if the warm isolate dies (native crash / OOM — plausible
      // for the larger model on a 6 GB phone) no result ever returns, so cap the
      // wait and surface ok:false → the lifecycle drops to manual instead of
      // wedging in "listening". (The old streaming engine had the same guard.)
      final text = await decode(samples).timeout(decodeTimeout);
      return SttResult(transcript: text.trim());
    } catch (e) {
      return SttResult(transcript: '', ok: false, error: '$e');
    }
  }

  @override
  Future<void> dispose() async {
    // NB: only tear down this engine's mic + partials. The warm recognizer
    // isolate is owned by AsrModelManager and must outlive the engine.
    await _micSub?.cancel();
    _micSub = null;
    if (!_partials.isClosed) await _partials.close();
    if (!_amplitude.isClosed) await _amplitude.close();
    _recorder?.dispose();
  }
}
