// TEMPORARY (Whisper/STT spike — see docs/.../2026-06-07-voice-rebuild-whisper-
// ondevice-spike.md). Throwaway kDebugMode probe that (1) records the §3 phrase
// set once on-device as 16 kHz mono WAVs, then (2) benchmarks each on-device
// OfflineRecognizer candidate (Whisper / Moonshine / Parakeet) by replaying the
// SAME WAVs and logging transcript + decode ms. Delete this file +
// whisper_spike_isolate.dart + the /whisper-spike route + the Settings tile once
// the decision lands. NOT production code.
//
// Setup on device (adb push): models → <externalFiles>/spike-whisper-base,
//   spike-whisper-small, spike-moonshine-base, spike-parakeet-tdt (Task S0).
// WAVs are recorded in-app (this screen) to <externalFiles>/spike-wavs/.
// Pull results: `adb shell cat <externalFiles>/whisper_spike_log.txt`
// (NOT adb pull — it returns a stale cache).

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'whisper_spike_isolate.dart';

class _Candidate {
  const _Candidate(this.label, this.dir, this.kind, this.files);
  final String label;
  final String dir; // sub-dir under externalFiles
  final String kind; // whisper | moonshine | transducer
  final Map<String, String> files; // logical key -> expected filename
}

// Expected sherpa-onnx release filenames (verified against the pushed models).
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

class _Phrase {
  const _Phrase(this.id, this.text, [this.hint = '']);
  final String id; // p1..p8 (== wav basename)
  final String text; // what to say
  final String hint;
}

// The §3 phrase set, verbatim. P8 is the noise pass (P2+P6 with background audio).
const _phrases = <_Phrase>[
  _Phrase('p1', 'I had heartburn about a 2', 'digit after a pause'),
  _Phrase('p2', 'For lunch I had a turkey sandwich and a cold brew coffee',
      'multi-noun meal'),
  _Phrase('p3', 'acid reflux', 'short symptom'),
  _Phrase('p4', 'bloating', 'single word'),
  _Phrase('p5', 'Aloha oatmeal chocolate chip protein bar', 'brand + "protein"'),
  _Phrase('p6', 'I had an IQ bar cookies and cream', 'THE brand-gating case'),
  _Phrase('p7', 'rate it 1 to 10', 'digit range'),
  _Phrase('p8',
      'For lunch I had a turkey sandwich and a cold brew coffee. I had an IQ bar cookies and cream',
      'NOISE PASS — play background audio while recording'),
];

const _kWavDir = 'spike-wavs';
const _kNumThreads = 4;

class WhisperSpikeScreen extends StatefulWidget {
  const WhisperSpikeScreen({super.key});

  @override
  State<WhisperSpikeScreen> createState() => _WhisperSpikeScreenState();
}

class _WhisperSpikeScreenState extends State<WhisperSpikeScreen> {
  final _recorder = AudioRecorder();
  _Candidate _selected = _candidates.first;
  bool _running = false;
  int? _recordingIdx; // which phrase is currently being recorded
  final Set<String> _recorded = {}; // phrase ids with a wav on disk
  int _taps = 0; // proves the UI thread stays alive (no ANR) during decode
  String _status = 'Record the 8 phrases, then pick a model and Run.';
  final List<String> _results = [];
  String _logPath = '';
  String _extPath = '';

  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _rx;
  Completer<void>? _ready;
  Completer<List<dynamic>>? _decode;

  @override
  void initState() {
    super.initState();
    getExternalStorageDirectory().then((d) {
      _extPath = d?.path ?? '';
      _logPath = '$_extPath/whisper_spike_log.txt';
      _refreshRecorded();
    });
  }

  @override
  void dispose() {
    _teardownIsolate();
    _recorder.dispose();
    super.dispose();
  }

  void _refreshRecorded() {
    if (_extPath.isEmpty) return;
    final dir = Directory('$_extPath/$_kWavDir');
    final present = <String>{};
    if (dir.existsSync()) {
      for (final p in _phrases) {
        if (File('${dir.path}/${p.id}.wav').existsSync()) present.add(p.id);
      }
    }
    setState(() {
      _recorded
        ..clear()
        ..addAll(present);
    });
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

  // --- Recording ------------------------------------------------------------

  Future<void> _toggleRecord(int i) async {
    if (_running) return;
    if (_recordingIdx == i) {
      try {
        await _recorder.stop();
      } catch (_) {}
      setState(() => _recordingIdx = null);
      _refreshRecorded();
      return;
    }
    if (_recordingIdx != null) return; // one at a time
    if (!await Permission.microphone.request().isGranted) {
      setState(() => _status = 'Mic permission denied.');
      return;
    }
    final dir = Directory('$_extPath/$_kWavDir')..createSync(recursive: true);
    final path = '${dir.path}/${_phrases[i].id}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          androidConfig: AndroidRecordConfig(
              audioSource: AndroidAudioSource.voiceRecognition),
        ),
        path: path,
      );
      setState(() {
        _recordingIdx = i;
        _status = 'Recording ${_phrases[i].id}… tap ⏹ when done.';
      });
    } catch (e) {
      setState(() => _status = 'Record failed: $e');
    }
  }

  // --- Benchmark ------------------------------------------------------------

  void _teardownIsolate() {
    _tx?.send(['dispose']);
    _rx?.close();
    _rx = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _tx = null;
  }

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
      final actual =
          dir.listSync().map((e) => e.path.split('/').last).join(', ');
      return 'MISSING ${missing.join(", ")} in ${c.dir}. Actual: [$actual].';
    }
    return resolved;
  }

  Future<void> _runAll() async {
    if (_running || _recordingIdx != null) return;
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
    setState(() => _status = '${c.label}: loaded ${loadMs}ms. Decoding…');

    for (final p in _phrases) {
      final wav = File('$_extPath/$_kWavDir/${p.id}.wav');
      if (!wav.existsSync()) {
        await _appendLog('model=${c.dir} phrase=${p.id} SKIP (no wav)');
        setState(() => _results.add('${p.id}  (not recorded)'));
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
            'model=${c.dir} phrase=${p.id} loadMs=$loadMs decodeMs=$ms text="$text"');
        setState(() => _results.add('${p.id}  ${ms}ms  "$text"'));
      } catch (e) {
        await _appendLog('model=${c.dir} phrase=${p.id} DECODE ERROR: $e');
        setState(() => _results.add('${p.id}  ERROR: $e'));
      }
    }

    _teardownIsolate();
    setState(() {
      _running = false;
      _status = '${c.label} done. Pick the next model, or cat the log.';
    });
  }

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
    return _int16ToFloat32(bd, 44, bytes.length); // fallback: 44-byte header
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
    final recordedCount = _recorded.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Whisper/STT spike')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => _taps++),
              child: Text('Responsiveness tap counter: $_taps (must stay live)'),
            ),
            const Divider(height: 28),
            Text('1) Record phrases  ($recordedCount/8)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (var i = 0; i < _phrases.length; i++) _recordRow(i),
            const Divider(height: 28),
            Text('2) Benchmark', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
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
            FilledButton(
              onPressed:
                  (_running || recordedCount == 0) ? null : _runAll,
              child: Text(_running ? 'Running…' : 'Run all phrases'),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _results.isEmpty ? '(results)' : _results.join('\n'),
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recordRow(int i) {
    final p = _phrases[i];
    final isRec = _recordingIdx == i;
    final done = _recorded.contains(p.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: _running ? null : () => _toggleRecord(i),
            icon: Icon(
              isRec ? Icons.stop_circle : Icons.fiber_manual_record,
              color: isRec ? Colors.red : (done ? Colors.green : Colors.grey),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p.id.toUpperCase()}${done ? "  ✓" : ""}  "${p.text}"',
                    style: const TextStyle(fontSize: 14)),
                if (p.hint.isNotEmpty)
                  Text(p.hint,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.black.withValues(alpha: 0.5))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
