// TEMPORARY (Whisper/STT spike — see docs/.../2026-06-07-voice-rebuild-whisper-
// ondevice-spike.md). Throwaway batch-ASR isolate that runs a sherpa-onnx
// OfflineRecognizer (Whisper / Moonshine / transducer) on a background isolate
// and times each decode. Delete with whisper_spike_screen.dart + its route +
// the Settings tile once the spike decision lands. NOT production code.
//
// Mirrors the streaming core/stt/asr_isolate.dart, but OFFLINE/batch: feed a
// whole utterance, decode once, return one result (no partials).

import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Messages UI->isolate:
///   ['init', kind ('whisper'|'moonshine'|'transducer'), Map<String,String> paths, numThreads]
///   ['decode', Float32List wholeUtterance]   (16 kHz mono, -1..1)
///   ['dispose']
/// Messages isolate->UI:
///   ['ready']
///   ['result', String text, int decodeMs]
///   ['error', String]
class WhisperSpikeIsolate {
  static void entry(SendPort mainSendPort) {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    sherpa.OfflineRecognizer? recognizer;

    port.listen((msg) {
      final m = msg as List;
      switch (m[0] as String) {
        case 'init':
          try {
            sherpa.initBindings();
            final kind = m[1] as String;
            final paths = (m[2] as Map).cast<String, String>();
            final numThreads = m[3] as int;
            recognizer = sherpa.OfflineRecognizer(
              sherpa.OfflineRecognizerConfig(
                model: _modelConfig(kind, paths, numThreads),
              ),
            );
            mainSendPort.send(['ready']);
          } catch (e) {
            mainSendPort.send(['error', 'init: $e']);
          }
          break;
        case 'decode':
          final r = recognizer;
          if (r == null) {
            mainSendPort.send(['error', 'decode before init']);
            break;
          }
          try {
            final samples = m[1] as Float32List;
            final t0 = DateTime.now();
            final s = r.createStream();
            s.acceptWaveform(samples: samples, sampleRate: 16000);
            r.decode(s);
            final text = r.getResult(s).text;
            s.free();
            final ms = DateTime.now().difference(t0).inMilliseconds;
            mainSendPort.send(['result', text, ms]);
          } catch (e) {
            mainSendPort.send(['error', 'decode: $e']);
          }
          break;
        case 'dispose':
          recognizer?.free();
          recognizer = null;
          break;
      }
    });
  }

  static sherpa.OfflineModelConfig _modelConfig(
    String kind,
    Map<String, String> p,
    int numThreads,
  ) {
    switch (kind) {
      case 'whisper':
        return sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: p['encoder']!,
            decoder: p['decoder']!,
          ),
          tokens: p['tokens']!,
          numThreads: numThreads,
          debug: false,
        );
      case 'moonshine':
        return sherpa.OfflineModelConfig(
          moonshine: sherpa.OfflineMoonshineModelConfig(
            preprocessor: p['preprocessor']!,
            encoder: p['encoder']!,
            uncachedDecoder: p['uncachedDecoder']!,
            cachedDecoder: p['cachedDecoder']!,
          ),
          tokens: p['tokens']!,
          numThreads: numThreads,
          debug: false,
        );
      case 'transducer':
        return sherpa.OfflineModelConfig(
          transducer: sherpa.OfflineTransducerModelConfig(
            encoder: p['encoder']!,
            decoder: p['decoder']!,
            joiner: p['joiner']!,
          ),
          tokens: p['tokens']!,
          numThreads: numThreads,
          debug: false,
        );
      default:
        throw ArgumentError('unknown model kind: $kind');
    }
  }
}
