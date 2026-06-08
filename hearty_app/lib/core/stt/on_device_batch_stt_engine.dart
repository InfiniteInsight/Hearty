import 'dart:async';
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
  });

  final double silenceSeconds;
  final int maxBufferSeconds;

  /// Decode a whole utterance to text (throws on failure). Supplied by the
  /// model manager from its warm isolate; the engine does not own it.
  final Future<String> Function(Float32List samples) decode;

  AudioRecorder? _recorder; // lazy: constructor touches native record
  final _partials = StreamController<String>.broadcast();
  final _buffer = BytesBuilder(copy: false);
  SilenceDetector? _silence;
  StreamSubscription? _micSub;
  void Function()? _onAutoSubmit;
  bool _capped = false;
  int get _maxBytes => maxBufferSeconds * _kSampleRate * 2;

  @override
  Stream<String> get partials => _partials.stream;

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
      final room = _maxBytes - _buffer.length;
      if (room > 0) _buffer.add(Uint8List.sublistView(bytes, 0, room));
      _capped = true;
      _onAutoSubmit?.call();
      return;
    }
    _buffer.add(bytes);
    final silence = _silence;
    if (silence != null && silence.addPcm(pcm16ToFloat32(bytes))) {
      _capped = true;
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
    final samples = normalizeAndPad(pcm16ToFloat32(pcm));
    try {
      final text = await decode(samples);
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
    _recorder?.dispose();
  }
}
