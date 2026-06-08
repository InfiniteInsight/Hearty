import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Long-lived batch ASR isolate. Creates a sherpa `OfflineRecognizer` once
/// (kept warm across decodes) and decodes whole utterances on demand. The
/// `kind` parameter selects the model config — `'moonshine'` | `'transducer'`
/// (Parakeet) | `'whisper'` — so one isolate serves every on-device model.
///
/// Messages UI->isolate:
///   ['init', kind, Map<String,String> paths, numThreads]
///   ['decode', Float32List wholeUtterance]   (16 kHz mono, -1..1)
///   ['dispose']
/// Messages isolate->UI:
///   ['ready']
///   ['result', String text]
///   ['error', String]
class BatchAsrIsolate {
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
            final s = r.createStream();
            s.acceptWaveform(samples: m[1] as Float32List, sampleRate: 16000);
            r.decode(s);
            final text = r.getResult(s).text;
            s.free();
            mainSendPort.send(['result', text]);
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
