// lib/features/voice/spike/sherpa_spike_screen.dart
//
// SPIKE — remove in 0R
// Throwaway screen that proves sherpa-onnx TTS works inside the app.
// The two helpers it uses (copyModelAssets, pcmToWav) are permanent and live in
// lib/core/tts/tts_audio_utils.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../../core/tts/tts_audio_utils.dart';

class SherpaSpikeScreen extends StatefulWidget {
  const SherpaSpikeScreen({super.key});

  @override
  State<SherpaSpikeScreen> createState() => _SherpaSpikeScreenState();
}

class _SherpaSpikeScreenState extends State<SherpaSpikeScreen> {
  static const _assetDir = 'assets/tts/vits-piper-en_US-libritts_r-medium';

  final _textController = TextEditingController(
    text: "Hi, I'm Hearty. I'll help you track how food makes you feel.",
  );
  final _player = AudioPlayer();

  // TTS engine — initialised lazily on first Speak press.
  sherpa_onnx.OfflineTts? _tts;
  bool _initialising = false;
  bool _ready = false;

  // Timing readouts
  String? _synthMs;
  String? _audioDurationMs;
  String? _rtf;
  String? _errorMessage;

  bool _speaking = false;

  @override
  void dispose() {
    _textController.dispose();
    _player.dispose();
    _tts?.free();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Initialisation (lazy, called on first Speak)
  // ---------------------------------------------------------------------------

  Future<void> _ensureReady() async {
    if (_ready) return;
    if (_initialising) return;
    setState(() {
      _initialising = true;
      _errorMessage = null;
    });

    try {
      final modelDir = await copyModelAssets(_assetDir);

      sherpa_onnx.initBindings();

      final vits = sherpa_onnx.OfflineTtsVitsModelConfig(
        model: '$modelDir/en_US-libritts_r-medium.onnx',
        tokens: '$modelDir/tokens.txt',
        dataDir: '$modelDir/espeak-ng-data',
      );
      final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
        vits: vits,
        numThreads: 2,
      );
      // Note: maxNumSenetences is the real field name in sherpa_onnx 1.13.2
      // (the typo is in the library itself — do not "fix" it).
      final config = sherpa_onnx.OfflineTtsConfig(
        model: modelConfig,
        maxNumSenetences: 1,
      );
      _tts = sherpa_onnx.OfflineTts(config);

      if (mounted) {
        setState(() {
          _ready = true;
          _initialising = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Init failed: $e';
          _initialising = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Speak
  // ---------------------------------------------------------------------------

  Future<void> _speak() async {
    if (_speaking) return;

    setState(() {
      _speaking = true;
      _errorMessage = null;
      _synthMs = null;
      _audioDurationMs = null;
      _rtf = null;
    });

    try {
      await _ensureReady();
      if (!_ready) {
        setState(() => _speaking = false);
        return;
      }

      final text = _textController.text.trim();
      if (text.isEmpty) {
        setState(() {
          _speaking = false;
          _errorMessage = 'Enter some text first.';
        });
        return;
      }

      // --- Synthesis (timed) ---
      final sw = Stopwatch()..start();
      final audio = _tts!.generate(text: text, sid: 0, speed: 1.0);
      sw.stop();
      final synthElapsed = sw.elapsedMilliseconds;

      final sampleCount = audio.samples.length;
      final sr = audio.sampleRate;
      final audioDuration =
          sr > 0 ? (sampleCount / sr * 1000).round() : 0;
      final rtf = audioDuration > 0
          ? (synthElapsed / audioDuration).toStringAsFixed(3)
          : 'N/A';

      // --- Convert to WAV and write temp file ---
      final wav = pcmToWav(audio.samples, sr);
      final tmpDir = await getTemporaryDirectory();
      final wavFile = File('${tmpDir.path}/hearty_spike.wav');
      await wavFile.writeAsBytes(wav, flush: true);

      // --- Play ---
      await _player.setFilePath(wavFile.path);
      await _player.play();

      if (mounted) {
        setState(() {
          _synthMs = '$synthElapsed ms';
          _audioDurationMs = '$audioDuration ms';
          _rtf = rtf;
          _speaking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _speaking = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sherpa TTS Spike'), // SPIKE — remove in 0R
        backgroundColor: Colors.deepOrange.shade100,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SPIKE banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade50,
                border: Border.all(color: Colors.deepOrange),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'SPIKE SCREEN — temporary, will be deleted in Phase 0R',
                style: TextStyle(
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _textController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Text to synthesise',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: (_speaking || _initialising) ? null : _speak,
              icon: _speaking || _initialising
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.record_voice_over),
              label: Text(_initialising
                  ? 'Loading model…'
                  : _speaking
                      ? 'Synthesising…'
                      : 'Speak'),
            ),
            const SizedBox(height: 24),

            // Timing readouts
            if (_synthMs != null) ...[
              const Text(
                'Timing',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _TimingRow(label: 'Synthesis time', value: _synthMs!),
              _TimingRow(label: 'Audio duration', value: _audioDurationMs!),
              _TimingRow(label: 'Real-time factor', value: _rtf!),
            ],

            // Error display
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
