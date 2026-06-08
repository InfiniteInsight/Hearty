import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'batch_asr_isolate.dart';
import 'on_device_model.dart';

/// Owns the on-device ASR model files (download + cache) and the **kept-warm**
/// recognizer isolate. The capture engine asks for a warm `decode` function;
/// the manager never blocks the capture path on a download — callers must
/// [ensureAndWarm] out-of-band (app start / settings change) and use
/// [warmDecodeOrNull] in the hot path.
class AsrModelManager {
  AsrModelManager({Future<String?> Function()? externalDir, Dio? dio})
      : _externalDir = externalDir ??
            (() async => (await getExternalStorageDirectory())?.path),
        _dio = dio ?? Dio();

  final Future<String?> Function() _externalDir;
  final Dio _dio;

  /// Re-warm the recognizer lazily after this much idle to free RAM (the warm
  /// model is 275 MB+ resident alongside the wake-word service on a 6 GB phone).
  static const idleRelease = Duration(minutes: 3);
  static const _numThreads = 4;

  // ── Model files: resolution + download (resolution is unit-testable) ───────

  /// Absolute paths for [spec]'s files if all present on disk, else null.
  Future<Map<String, String>?> resolvePaths(OnDeviceModelSpec spec) async {
    final base = await _externalDir();
    if (base == null) return null;
    final dir = '$base/${spec.dir}';
    final resolved = <String, String>{};
    for (final e in spec.files.entries) {
      final f = File('$dir/${e.value}');
      if (!f.existsSync()) return null;
      resolved[e.key] = f.path;
    }
    return resolved;
  }

  Future<bool> isReady(OnDeviceModel model) async =>
      (await resolvePaths(model.spec)) != null;

  /// Download + extract [model] if not already present. Safe to call when ready
  /// (no-op). Device path: pulls the sherpa-onnx .tar.bz2, bunzips + untars only
  /// the files the spec needs into the model dir, then verifies. On a corrupt/
  /// partial archive the dir is cleared so the next call re-downloads.
  Future<void> ensureModel(
    OnDeviceModel model, {
    void Function(double progress)? onProgress,
  }) async {
    if (await isReady(model)) return;
    final base = await _externalDir();
    if (base == null) throw StateError('no external storage dir');
    final spec = model.spec;
    final dir = Directory('$base/${spec.dir}')..createSync(recursive: true);
    final tmp = '${(await getTemporaryDirectory()).path}/${spec.dir}.tar.bz2';

    try {
      if (kDebugMode) {
        debugPrint('[asr] downloading ${spec.dir} from ${spec.downloadUrl}');
      }
      await _dio.download(
        spec.downloadUrl,
        tmp,
        onReceiveProgress: (r, t) {
          if (t > 0 && onProgress != null) onProgress(r / t);
        },
      );
      if (kDebugMode) debugPrint('[asr] downloaded ${spec.dir}, extracting…');
      final dirPath = dir.path;
      final wanted = spec.files.values.toSet();
      // Extract OFF the main isolate: bunzip+untar of a ~240 MB archive is heavy
      // pure-Dart CPU work that ANRs the UI thread if run inline (confirmed on
      // the Pixel 4a). Stream bz2 → a temp .tar → individual files so peak
      // memory stays bounded (no 240 MB readAsBytes + 280 MB decode in RAM).
      await Isolate.run(() {
        final tarPath = '$tmp.tar';
        final bzIn = InputFileStream(tmp);
        final tarOut = OutputFileStream(tarPath);
        BZip2Decoder().decodeStream(bzIn, tarOut);
        bzIn.closeSync();
        tarOut.closeSync();
        final tarIn = InputFileStream(tarPath);
        final archive = TarDecoder().decodeBuffer(tarIn);
        for (final f in archive.files) {
          if (!f.isFile) continue;
          final name = f.name.split('/').last;
          if (!wanted.contains(name)) continue; // skip README/test_wavs/etc.
          final out = OutputFileStream('$dirPath/$name');
          f.writeContent(out);
          out.closeSync();
        }
        tarIn.closeSync();
        try {
          File(tarPath).deleteSync();
        } catch (_) {}
      });
      if (kDebugMode) debugPrint('[asr] extracted ${spec.dir}');
    } finally {
      try {
        File(tmp).deleteSync();
      } catch (_) {}
    }

    if (!await isReady(model)) {
      // Incomplete/corrupt extraction — clear so the next attempt re-downloads.
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
      throw StateError('model ${spec.dir} extraction incomplete');
    }
  }

  // ── Keep-warm recognizer isolate (manager-owned; survives engines) ─────────

  OnDeviceModel? _warmModel;
  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _rx;
  Completer<void>? _ready;
  Completer<String>? _decode;
  Timer? _idleTimer;

  /// A warm decode fn for [model] if it's loaded right now, else null. The hot
  /// path uses this and never awaits a load/download.
  Future<String> Function(Float32List)? warmDecodeOrNull(OnDeviceModel model) {
    if (_warmModel == model && _tx != null) return _decodeSamples;
    return null;
  }

  Future<void>? _warming;
  OnDeviceModel? _warmingModel;

  /// Ensure [model] is downloaded and its recognizer warm. Call out-of-band.
  ///
  /// In-flight guard: the capture path fires this on *every* not-ready
  /// session-open, so repeated mic taps during the first-run download would
  /// otherwise spawn concurrent `_dio.download` calls writing the same temp
  /// path (and racing isolate spawns). Concurrent calls for the same model
  /// share one operation.
  Future<void> ensureAndWarm(
    OnDeviceModel model, {
    void Function(double progress)? onProgress,
  }) {
    final existing = _warming;
    if (existing != null && _warmingModel == model) return existing;
    late final Future<void> f;
    f = _ensureAndWarm(model, onProgress: onProgress).whenComplete(() {
      if (identical(_warming, f)) {
        _warming = null;
        _warmingModel = null;
      }
    });
    _warming = f;
    _warmingModel = model;
    return f;
  }

  Future<void> _ensureAndWarm(
    OnDeviceModel model, {
    void Function(double progress)? onProgress,
  }) async {
    await ensureModel(model, onProgress: onProgress);
    if (_warmModel == model && _tx != null) {
      _bumpIdle();
      return;
    }
    await _disposeIsolate(); // switching models — drop the old one
    final paths = await resolvePaths(model.spec);
    if (paths == null) throw StateError('model not ready after ensure');

    _rx = ReceivePort();
    _ready = Completer<void>();
    _isolate = await Isolate.spawn(BatchAsrIsolate.entry, _rx!.sendPort);
    _rx!.listen((msg) {
      if (msg is SendPort) {
        _tx = msg;
        _tx!.send(['init', model.spec.kind, paths, _numThreads]);
        return;
      }
      final m = msg as List;
      switch (m[0] as String) {
        case 'ready':
          if (_ready?.isCompleted == false) _ready!.complete();
          break;
        case 'result':
          if (_decode?.isCompleted == false) _decode!.complete(m[1] as String);
          break;
        case 'error':
          final e = m[1] as String;
          if (_ready?.isCompleted == false) _ready!.completeError(e);
          if (_decode?.isCompleted == false) _decode!.completeError(e);
          break;
      }
    });
    await _ready!.future;
    _warmModel = model;
    _bumpIdle();
    if (kDebugMode) debugPrint('[asr] recognizer warm: ${model.spec.dir}');
  }

  Future<String> _decodeSamples(Float32List samples) async {
    final tx = _tx;
    if (tx == null) throw StateError('recognizer not warm');
    _bumpIdle();
    _decode = Completer<String>();
    final sw = kDebugMode ? (Stopwatch()..start()) : null;
    tx.send(['decode', samples]);
    final text = await _decode!.future;
    if (kDebugMode) {
      final secs = (samples.length / 16000).toStringAsFixed(1);
      debugPrint('[asr] decode ${sw!.elapsedMilliseconds}ms '
          '(${secs}s audio) -> ${text.isEmpty ? "<BLANK>" : '"$text"'}');
    }
    return text;
  }

  void _bumpIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleRelease, () => unawaited(_disposeIsolate()));
  }

  Future<void> _disposeIsolate() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    // Strand-proof a reap/model-switch mid-decode: any future awaiting the
    // isolate must be completed (with an error) before we kill it, or the
    // engine's `decode(...)` would hang until its own timeout. The engine maps
    // ok:false → manual, so an error here is the correct, prompt outcome.
    if (_decode?.isCompleted == false) {
      _decode!.completeError(StateError('recognizer isolate disposed'));
    }
    if (_ready?.isCompleted == false) {
      _ready!.completeError(StateError('recognizer isolate disposed'));
    }
    _decode = null;
    _ready = null;
    _tx?.send(['dispose']);
    _rx?.close();
    _rx = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _tx = null;
    _warmModel = null;
  }

  Future<void> dispose() => _disposeIsolate();
}
