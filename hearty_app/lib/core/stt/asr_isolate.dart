import 'dart:isolate';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Long-lived background isolate running sherpa-onnx streaming ASR, so model
/// loading and per-chunk decode never block the UI thread (the spike decoded on
/// the main isolate and ANR'd). FFI pointers can't cross isolates, so the
/// recognizer is created AND used entirely in here.
///
/// UI → isolate:
///   ['init', encoder, decoder, joiner, tokens, numThreads]
///   ['pcm', Float32List]      — a mic chunk (16 kHz mono, -1..1)
///   ['finish']                — flush + return final; recognizer stays warm
///   ['dispose']               — free native resources
/// isolate → UI:
///   ['ready'] | ['partial', String] | ['final', String] | ['error', String]
class AsrIsolate {
  /// Isolate entry point. Sends its [SendPort] back on [mainSendPort] first,
  /// then streams result messages.
  static void entry(SendPort mainSendPort) {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    sherpa.OnlineRecognizer? recognizer;
    sherpa.OnlineStream? stream;

    port.listen((msg) {
      final m = msg as List;
      switch (m[0] as String) {
        case 'init':
          try {
            sherpa.initBindings();
            recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
              model: sherpa.OnlineModelConfig(
                transducer: sherpa.OnlineTransducerModelConfig(
                  encoder: m[1] as String,
                  decoder: m[2] as String,
                  joiner: m[3] as String,
                ),
                tokens: m[4] as String,
                numThreads: m[5] as int,
                debug: false,
              ),
              // WE decide turn-end (via the SilenceDetector on the UI side),
              // not the engine — this is the whole point of the rebuild.
              enableEndpoint: false,
            ));
            stream = recognizer!.createStream();
            mainSendPort.send(['ready']);
          } catch (e) {
            mainSendPort.send(['error', 'init: $e']);
          }
          break;
        case 'pcm':
          final r = recognizer, s = stream;
          if (r == null || s == null) break;
          try {
            s.acceptWaveform(samples: m[1] as Float32List, sampleRate: 16000);
            while (r.isReady(s)) {
              r.decode(s);
            }
            mainSendPort.send(['partial', r.getResult(s).text]);
          } catch (e) {
            mainSendPort.send(['error', 'pcm: $e']);
          }
          break;
        case 'finish':
          final r = recognizer, s = stream;
          if (r == null || s == null) {
            mainSendPort.send(['final', '']);
            break;
          }
          try {
            final text = r.getResult(s).text;
            r.reset(s); // ready for the next turn; recognizer stays warm
            mainSendPort.send(['final', text]);
          } catch (e) {
            mainSendPort.send(['error', 'finish: $e']);
          }
          break;
        case 'dispose':
          stream?.free();
          recognizer?.free();
          recognizer = null;
          stream = null;
          break;
      }
    });
  }
}
