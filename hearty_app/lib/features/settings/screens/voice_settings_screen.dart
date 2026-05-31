import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/tts/tts_voice_preference.dart';
import '../../voice/providers/voice_provider.dart';

class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  ConsumerState<VoiceSettingsScreen> createState() =>
      _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  final FlutterTts _tts = FlutterTts();
  List<Map<String, String>> _voices = [];
  String? _previewingVoice;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVoices();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _previewingVoice = null);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.7);
    final raw = await _tts.getVoices as List<dynamic>? ?? [];
    final english = raw
        .map((v) => Map<String, String>.from(
            (v as Map).map((k, val) => MapEntry(k.toString(), val.toString()))))
        .where((v) {
          final locale = (v['locale'] ?? '').toLowerCase();
          return locale.startsWith('en');
        })
        .toList()
      ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    if (mounted) {
      setState(() {
        _voices = english;
        _loading = false;
      });
    }
  }

  Future<void> _preview(String voiceName, String locale) async {
    await _tts.stop();
    setState(() => _previewingVoice = voiceName);
    await _tts.setVoice({'name': voiceName, 'locale': locale});
    await _tts.speak(
        "Hi, I'm Hearty. I'll help you track how food makes you feel.");
  }

  Future<void> _select(String? voiceName) async {
    await _tts.stop();
    setState(() => _previewingVoice = null);
    await ref.read(ttsVoiceProvider.notifier).setVoice(voiceName);
    // Re-init VoiceNotifier so the next voice interaction uses the new voice.
    ref.invalidate(voiceProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(voiceName == null ? 'Restored default voice' : 'Voice saved'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedVoice = ref.watch(ttsVoiceProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice'),
        actions: [
          if (savedVoice != null)
            TextButton(
              onPressed: () => _select(null),
              child: const Text('Reset'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _voices.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No English voices found on this device.\n\n'
                      'Install additional voices in Android Settings → '
                      'General management → Language → Text-to-speech.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _voices.length,
                  itemBuilder: (context, index) {
                    final voice = _voices[index];
                    final name = voice['name'] ?? '';
                    final locale = voice['locale'] ?? 'en-US';
                    final isSelected = name == savedVoice;
                    final isPreviewing = name == _previewingVoice;

                    return ListTile(
                      leading: isSelected
                          ? Icon(Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary)
                          : const Icon(Icons.radio_button_unchecked),
                      title: Text(_friendlyName(name)),
                      subtitle: Text(locale),
                      trailing: IconButton(
                        icon: isPreviewing
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              )
                            : const Icon(Icons.play_arrow_outlined),
                        tooltip: 'Preview',
                        onPressed:
                            isPreviewing ? null : () => _preview(name, locale),
                      ),
                      onTap: () => _select(name),
                    );
                  },
                ),
    );
  }

  // Turns e.g. "en-us-x-sfg-local" into "en-US · sfg (local)"
  static String _friendlyName(String raw) {
    final parts = raw.split('-');
    if (parts.length < 4) return raw;
    final tag = parts.skip(3).join('-');
    final lang = '${parts[0].toUpperCase()}-${parts[1].toUpperCase()}';
    return '$lang · $tag';
  }
}
