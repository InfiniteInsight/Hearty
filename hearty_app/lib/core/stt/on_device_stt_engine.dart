import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'asr_isolate.dart';
import 'asr_model_locator.dart';
import 'silence_detector.dart';
import 'stt_engine.dart';

const _kSampleRate = 16000;

/// On-device [SttEngine]: owns a `record` PCM16 mic stream and forwards audio to
/// a long-lived [AsrIsolate] (sherpa streaming, endpointing off) while a
/// [SilenceDetector] drives optional auto-submit. Fully offline.
class OnDeviceSttEngine implements SttEngine {
  OnDeviceSttEngine({required this.silenceSeconds});
  final double silenceSeconds;

  final _recorder = AudioRecorder();
  final _partials = StreamController<String>.broadcast();
  final _readyOrError = Completer<String?>(); // null = ready, else error text
  final _finalCompleter = Completer<String>();

  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _rx;
  StreamSubscription? _micSub;
  SilenceDetector? _silence;
  bool _finishing = false;

  @override
  Stream<String> get partials => _partials.stream;

  @override
  Future<void> start({void Function()? onAutoSubmit}) async {
    final model = await AsrModelLocator.resolve();
    if (model == null) {
      throw StateError('on-device ASR model not found');
    }
    _silence = onAutoSubmit == null
        ? null
        : SilenceDetector(
            sampleRate: _kSampleRate, silenceSeconds: silenceSeconds);

    _rx = ReceivePort();
    _isolate = await Isolate.spawn(AsrIsolate.entry, _rx!.sendPort);
    _rx!.listen((msg) {
      if (msg is SendPort) {
        _tx = msg;
        _tx!.send([
          'init',
          model.encoder,
          model.decoder,
          model.joiner,
          model.tokens,
          4,
        ]);
        return;
      }
      final m = msg as List;
      switch (m[0] as String) {
        case 'ready':
          if (!_readyOrError.isCompleted) _readyOrError.complete(null);
          break;
        case 'partial':
          if (!_partials.isClosed) _partials.add(m[1] as String);
          break;
        case 'final':
          if (!_finalCompleter.isCompleted) {
            _finalCompleter.complete(m[1] as String);
          }
          break;
        case 'error':
          if (!_readyOrError.isCompleted) _readyOrError.complete(m[1] as String);
          if (!_finalCompleter.isCompleted) _finalCompleter.complete('');
          break;
      }
    });

    final err = await _readyOrError.future;
    if (err != null) throw StateError('ASR init failed: $err');

    final mic = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: 1,
      androidConfig:
          AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
    ));
    _micSub = mic.listen((bytes) {
      if (_finishing) return;
      final samples = _pcm16ToFloat32(bytes);
      _tx?.send(['pcm', samples]);
      if (_silence != null && _silence!.addPcm(samples)) {
        onAutoSubmit?.call();
      }
    });
  }

  @override
  Future<SttResult> stop() async {
    _finishing = true;
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    _tx?.send(['finish']);
    final text = await _finalCompleter.future
        .timeout(const Duration(seconds: 2), onTimeout: () => '');
    return SttResult(transcript: text.trim());
  }

  @override
  Future<void> dispose() async {
    _tx?.send(['dispose']);
    await _micSub?.cancel();
    _micSub = null;
    _rx?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    if (!_partials.isClosed) await _partials.close();
    _recorder.dispose();
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
}
