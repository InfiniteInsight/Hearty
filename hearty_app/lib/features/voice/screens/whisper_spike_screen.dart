// TEMPORARY (Whisper/STT spike — see docs/.../2026-06-07-voice-rebuild-whisper-
// ondevice-spike.md). Throwaway kDebugMode probe that benchmarks on-device
// OfflineRecognizer candidates (Whisper / Moonshine / Parakeet) by replaying the
// same pre-recorded §3 phrase WAVs to each and logging transcript + decode ms.
// Delete this file + whisper_spike_isolate.dart + the /whisper-spike route + the
// Settings tile once the decision lands. NOT production code.
//
// Setup on device (adb push):
//   models → <externalFiles>/spike-whisper-base, spike-whisper-small,
//            spike-moonshine-base, spike-parakeet-tdt   (see plan Task S0)
//   wavs   → <externalFiles>/spike-wavs/p1.wav … p8.wav (plan Task S1)
// Pull results with `adb shell cat <externalFiles>/whisper_spike_log.txt`
// (NOT adb pull — it returns a stale cache).

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'whisper_spike_isolate.dart';

class _Candidate {
  const _Candidate(this.label, this.dir, this.kind, this.files);
  final String label;
  final String dir; // sub-dir under externalFiles
  final String kind; // whisper | moonshine | transducer
  final Map<String, String> files; // logical key -> expected filename
}

// Expected sherpa-onnx release filenames. If a tarball uses different names, the
// "Run" button reports the dir's actual contents so they can be corrected.
const _candidates = <_Candidate>[
  _Candidate('Whisper base.en int8', 'spike-whisper-base', 'whisper', {
    'encoder': 'base.en-encoder.int8.onnx',
    'decoder': 'base.en-decoder.int8.onnx',
    'tokens': 'base.en-tokens.txt',
  }),
  _Candidate('Whisper small.en int8', 'spike-whisper-small', 'whisper', {
    'encoder': 'small.en-encoder.int8.onnx',
    'decoder': 'small.en-decoder.int8.onnx',
    'tokens': 'small.en-tokens.txt',
  }),
  _Candidate('Moonshine base int8', 'spike-moonshine-base', 'moonshine', {
    'preprocessor': 'preprocess.onnx',
    'encoder': 'encode.int8.onnx',
    'uncachedDecoder': 'uncached_decode.int8.onnx',
    'cachedDecoder': 'cached_decode.int8.onnx',
    'tokens': 'tokens.txt',
  }),
  _Candidate('Parakeet-TDT 0.6b int8', 'spike-parakeet-tdt', 'transducer', {
    'encoder': 'encoder.int8.onnx',
    'decoder': 'decoder.int8.onnx',
    'joiner': 'joiner.int8.onnx',
    'tokens': 'tokens.txt',
  }),
];

const _kWavDir = 'spike-wavs';
const _kPhrases = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
const _kNumThreads = 4;

class WhisperSpikeScreen extends StatefulWidget {
  const WhisperSpikeScreen({super.key});

  @override
  State<WhisperSpikeScreen> createState() => _WhisperSpikeScreenState();
}

class _WhisperSpikeScreenState extends State<WhisperSpikeScreen> {
  _Candidate _selected = _candidates.first;
  bool _running = false;
  int _taps = 0; // proves the UI thread stays alive (no ANR) during decode
  String _status = 'Pick a model, tap "Run all phrases". '
      'Keep tapping the counter — it must stay live (no ANR).';
  final List<String> _results = [];
  String _logPath = '';
  String _extPath = '';

  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _rx;
  Completer<void>? _ready;
  Completer<List<dynamic>>? _decode; // completes with ['result', text, ms]

  @override
  void initState() {
    super.initState();
    getExternalStorageDirectory().then((d) {
      _extPath = d?.path ?? '';
      _logPath = '$_extPath/whisper_spike_log.txt';
    });
  }

  @override
  void dispose() {
    _teardownIsolate();
    super.dispose();
  }

  Future<void> _appendLog(String line) async {
    if (_logPath.isEmpty) return;
    try {
      await File(_logPath).writeAsString(
        '${DateTime.now().toIso8601String()}  [SPIKE] $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  void _teardownIsolate() {
    _tx?.send(['dispose']);
    _rx?.close();
    _rx = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _tx = null;
  }

  /// Resolve a candidate's model files to absolute paths, or return an error
  /// string listing the dir's actual contents so names can be corrected.
  Future<Object> _resolvePaths(_Candidate c) async {
    final dir = Directory('$_extPath/${c.dir}');
    if (!dir.existsSync()) {
      return 'NO DIR: ${dir.path} — adb push the model there (Task S0).';
    }
    final resolved = <String, String>{};
    final missing = <String>[];
    for (final entry in c.files.entries) {
      final f = File('${dir.path}/${entry.value}');
      if (f.existsSync()) {
        resolved[entry.key] = f.path;
      } else {
        missing.add(entry.value);
      }
    }
    if (missing.isNotEmpty) {
      final actual = dir
          .listSync()
          .map((e) => e.path.split('/').last)
          .join(', ');
      return 'MISSING ${missing.join(", ")} in ${c.dir}. '
          'Actual files: [$actual]. Fix the names in _candidates.';
    }
    return resolved;
  }

  Future<void> _runAll() async {
    if (_running) return;
    final c = _selected;
    setState(() {
      _running = true;
      _results.clear();
      _status = 'Resolving ${c.label}…';
    });

    final paths = await _resolvePaths(c);
    if (paths is String) {
      setState(() {
        _running = false;
        _status = paths;
      });
      return;
    }
    final modelPaths = paths as Map<String, String>;

    // Spawn the batch isolate and init the model (timed = loadMs).
    _rx = ReceivePort();
    _ready = Completer<void>();
    _isolate = await Isolate.spawn(WhisperSpikeIsolate.entry, _rx!.sendPort);
    _rx!.listen((msg) {
      if (msg is SendPort) {
        _tx = msg;
        return;
      }
      final m = msg as List;
      switch (m[0] as String) {
        case 'ready':
          if (_ready?.isCompleted == false) _ready!.complete();
          break;
        case 'result':
          if (_decode?.isCompleted == false) _decode!.complete(m);
          break;
        case 'error':
          final err = m[1] as String;
          if (_ready?.isCompleted == false) _ready!.completeError(err);
          if (_decode?.isCompleted == false) _decode!.completeError(err);
          break;
      }
    });

    // Wait for the isolate to hand us its SendPort before init.
    while (_tx == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final loadStart = DateTime.now();
    _tx!.send(['init', c.kind, modelPaths, _kNumThreads]);
    try {
      await _ready!.future;
    } catch (e) {
      await _appendLog('model=${c.dir} INIT FAILED: $e');
      setState(() {
        _running = false;
        _status = 'INIT FAILED (${c.label}): $e';
      });
      _teardownIsolate();
      return;
    }
    final loadMs = DateTime.now().difference(loadStart).inMilliseconds;
    await _appendLog('model=${c.dir} loadMs=$loadMs (init ok)');
    setState(() => _status =
        '${c.label}: loaded in ${loadMs}ms. Decoding phrases…');

    // Replay each phrase WAV through the same recognizer.
    for (final p in _kPhrases) {
      final wav = File('$_extPath/$_kWavDir/$p.wav');
      if (!wav.existsSync()) {
        await _appendLog('model=${c.dir} phrase=$p SKIP (no wav)');
        continue;
      }
      final samples = _wavToFloat32(await wav.readAsBytes());
      _decode = Completer<List<dynamic>>();
      _tx!.send(['decode', samples]);
      try {
        final res = await _decode!.future;
        final text = res[1] as String;
        final ms = res[2] as int;
        await _appendLog(
            'model=${c.dir} phrase=$p loadMs=$loadMs decodeMs=$ms text="$text"');
        setState(() => _results.add('$p  ${ms}ms  "$text"'));
      } catch (e) {
        await _appendLog('model=${c.dir} phrase=$p DECODE ERROR: $e');
        setState(() => _results.add('$p  ERROR: $e'));
      }
    }

    _teardownIsolate();
    setState(() {
      _running = false;
      _status = '${c.label} done. `adb shell cat` the log. Run the next model.';
    });
  }

  /// Parse a 16 kHz mono PCM16 WAV into normalized Float32 by locating the
  /// 'data' subchunk (tolerates extra header chunks).
  static Float32List _wavToFloat32(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    var i = 12; // skip RIFF/WAVE header
    while (i + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(i, i + 4));
      final size = bd.getUint32(i + 4, Endian.little);
      final start = i + 8;
      if (id == 'data') {
        final end = (start + size <= bytes.length) ? start + size : bytes.length;
        return _int16ToFloat32(bd, start, end);
      }
      i = start + size + (size.isOdd ? 1 : 0);
    }
    // Fallback: assume a standard 44-byte header.
    return _int16ToFloat32(bd, 44, bytes.length);
  }

  static Float32List _int16ToFloat32(ByteData bd, int start, int end) {
    final n = (end - start) ~/ 2;
    final out = Float32List(n);
    for (var j = 0; j < n; j++) {
      out[j] = bd.getInt16(start + j * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Whisper/STT spike (benchmark)')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButton<_Candidate>(
              value: _selected,
              isExpanded: true,
              onChanged: _running
                  ? null
                  : (c) => setState(() => _selected = c ?? _selected),
              items: [
                for (final c in _candidates)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
            ),
            const SizedBox(height: 8),
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _taps++),
              child: Text('Responsiveness tap counter: $_taps'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _results.isEmpty ? '(results)' : _results.join('\n'),
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _running ? null : _runAll,
              child: Text(_running ? 'Running…' : 'Run all phrases'),
            ),
          ],
        ),
      ),
    );
  }
}
