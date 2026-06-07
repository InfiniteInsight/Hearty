// TEMPORARY (Plan B, P0/B0.2): throwaway device-gate probe — proves the ASR
// isolate decodes a live mic stream with NO ANR on the Pixel 4a. Delete this
// file + its route + the Settings tile once the gate passes and B1 lands.
//
// Reads the on-device model from <externalFiles>/asr-model (push the 122MB int8
// model there first). Logs sessions to <externalFiles>/asr_spike_log.txt with an
// [ISOLATE-PROBE] tag so results can be `adb shell cat`'d.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../core/stt/asr_isolate.dart';
import '../../wake_word/wake_word_channel.dart';

const _kSampleRate = 16000;

class AsrIsolateProbeScreen extends StatefulWidget {
  const AsrIsolateProbeScreen({super.key});

  @override
  State<AsrIsolateProbeScreen> createState() => _AsrIsolateProbeScreenState();
}

class _AsrIsolateProbeScreenState extends State<AsrIsolateProbeScreen> {
  final _recorder = AudioRecorder();
  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _rx;
  StreamSubscription? _micSub;

  bool _listening = false;
  String _status = 'Tap Start. UI must stay responsive (tap counter) = no ANR.';
  String _transcript = '';
  String _logPath = '';
  int _taps = 0; // proves the UI thread is alive while ASR decodes

  @override
  void initState() {
    super.initState();
    getExternalStorageDirectory()
        .then((d) => _logPath = '${d?.path}/asr_spike_log.txt');
  }

  @override
  void dispose() {
    _teardown();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _appendLog(String line) async {
    if (_logPath.isEmpty) return;
    try {
      await File(_logPath).writeAsString(
        '${DateTime.now().toIso8601String()}  [ISOLATE-PROBE] $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> _start() async {
    if (_listening) return;
    if (!await Permission.microphone.request().isGranted) {
      setState(() => _status = 'Mic permission denied.');
      return;
    }
    final ext = await getExternalStorageDirectory();
    final dir = '${ext?.path}/asr-model';
    final enc = File('$dir/encoder.int8.onnx');
    if (!enc.existsSync()) {
      setState(() => _status = 'NO MODEL at $dir — adb push the 122MB model there.');
      return;
    }

    _rx = ReceivePort();
    _isolate = await Isolate.spawn(AsrIsolate.entry, _rx!.sendPort);
    final readyOrErr = Completer<void>();
    _rx!.listen((msg) {
      if (msg is SendPort) {
        _tx = msg;
        _tx!.send(['init', '$dir/encoder.int8.onnx', '$dir/decoder.int8.onnx',
          '$dir/joiner.int8.onnx', '$dir/tokens.txt', 4]);
        return;
      }
      final m = msg as List;
      switch (m[0] as String) {
        case 'ready':
          if (!readyOrErr.isCompleted) readyOrErr.complete();
          break;
        case 'partial':
          setState(() => _transcript = m[1] as String);
          break;
        case 'final':
          setState(() {
            _transcript = m[1] as String;
            _status = 'Final received. Saved to log.';
          });
          _appendLog('FINAL: "${m[1]}"');
          break;
        case 'error':
          setState(() => _status = 'ERROR: ${m[1]}');
          _appendLog('ERROR: ${m[1]}');
          break;
      }
    });
    await readyOrErr.future;
    await _appendLog('READY (isolate init ok)');

    try {
      await WakeWordChannel.stopListening();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final mic = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: 1,
      androidConfig:
          AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
    ));
    setState(() {
      _listening = true;
      _transcript = '';
      _status = 'LIVE — speak; keep tapping the counter to check responsiveness.';
    });
    _micSub = mic.listen((bytes) => _tx?.send(['pcm', _pcm16ToFloat32(bytes)]));
  }

  Future<void> _stop() async {
    if (!_listening) return;
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    _tx?.send(['finish']);
    try {
      await WakeWordChannel.startListening();
    } catch (_) {}
    setState(() => _listening = false);
  }

  void _teardown() {
    _tx?.send(['dispose']);
    _micSub?.cancel();
    _rx?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ASR isolate probe (no-ANR gate)')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    _transcript.isEmpty ? '(transcript)' : _transcript,
                    style: const TextStyle(fontSize: 22, height: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: _listening ? null : _start,
                  child: const Text('Start'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _listening ? _stop : null,
                  child: const Text('Stop'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
