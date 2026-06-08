import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models/user_preferences.dart';
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/stt/on_device_model.dart';
import '../../voice/providers/voice_provider.dart';

/// Settings for speech-to-text **dictation** (the input side). Distinct from the
/// TTS voice picker at `/settings/voice` (the output side). Auto-saves on change,
/// consistent with the other settings pages.
///
/// Three controls, all wired to live consumption in `VoiceNotifier`:
///   • Transcription model (Moonshine default / Parakeet) — switching downloads
///     + warms via the shared [asrModelManagerProvider]; the pref only flips
///     once the model is actually ready, so a failed download leaves the working
///     model selected.
///   • Auto-submit on/off + trailing-silence seconds slider (2–5 s).
///   • Advanced → Use cloud when online (dormant by default).
class DictationSettingsScreen extends ConsumerStatefulWidget {
  const DictationSettingsScreen({super.key});

  @override
  ConsumerState<DictationSettingsScreen> createState() =>
      _DictationSettingsScreenState();
}

class _DictationSettingsScreenState
    extends ConsumerState<DictationSettingsScreen> {
  // Non-null while a model download/warm is in flight (drives the progress row
  // and blocks a second concurrent switch).
  OnDeviceModel? _switchingTo;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(preferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Dictation')),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load preferences: $e')),
        data: (prefs) => ListView(
          children: [
            _sectionHeader(context, 'Transcription model'),
            _modelPicker(prefs),
            if (_switchingTo != null) _downloadRow(),
            const Divider(),
            _sectionHeader(context, 'Auto-submit'),
            SwitchListTile(
              secondary: const Icon(Icons.send_outlined),
              title: const Text('Auto-submit after a pause'),
              subtitle: const Text(
                  'Send automatically once you stop talking, instead of '
                  'tapping submit.'),
              value: prefs.autoSubmit,
              onChanged: (v) => _save(prefs.copyWith(autoSubmit: v)),
            ),
            _silenceSlider(prefs),
            const Divider(),
            _sectionHeader(context, 'Advanced'),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_outlined),
              title: const Text('Use cloud when online'),
              subtitle: const Text(
                  'Transcribe with the cloud service while connected. Off by '
                  'default — Hearty transcribes on your device.'),
              value: prefs.useCloudWhenOnline,
              onChanged: (v) => _save(prefs.copyWith(useCloudWhenOnline: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary)),
      );

  Widget _modelPicker(UserPreferences prefs) {
    final selected = OnDeviceModel.fromPrefString(prefs.useOnDeviceModel);
    return RadioGroup<OnDeviceModel>(
      groupValue: selected,
      onChanged: (m) {
        // Ignore taps mid-switch so downloads don't stack; re-selecting the
        // current model is a no-op. (Tiles are also disabled while switching.)
        if (_switchingTo != null) return;
        if (m != null && m != selected) _switchModel(prefs, m);
      },
      child: Column(
        children: [
          for (final model in OnDeviceModel.values)
            RadioListTile<OnDeviceModel>(
              title: Text(model.label),
              subtitle: Text(model.blurb),
              value: model,
              enabled: _switchingTo == null,
            ),
        ],
      ),
    );
  }

  Widget _downloadRow() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preparing ${_switchingTo!.label}… dictation is limited until '
              'it’s ready.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
                value: _progress > 0 && _progress < 1 ? _progress : null),
          ],
        ),
      );

  Widget _silenceSlider(UserPreferences prefs) {
    final seconds = prefs.autoSubmitSilenceSeconds;
    return ListTile(
      enabled: prefs.autoSubmit,
      title: const Text('Pause before auto-submit'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${seconds.toStringAsFixed(1)} s'),
          Slider(
            min: 2.0,
            max: 5.0,
            divisions: 6, // 0.5 s steps
            label: '${seconds.toStringAsFixed(1)} s',
            value: seconds.clamp(2.0, 5.0),
            onChanged: prefs.autoSubmit
                ? (v) => _save(prefs.copyWith(autoSubmitSilenceSeconds: v))
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _save(UserPreferences prefs) =>
      ref.read(preferencesProvider.notifier).save(prefs);

  /// Persist-after-ready: download + warm the new model first, then flip the
  /// pref. On failure the working model stays selected (no half-broken state
  /// where the pref points at a model that never downloaded).
  Future<void> _switchModel(UserPreferences prefs, OnDeviceModel model) async {
    setState(() {
      _switchingTo = model;
      _progress = 0;
    });
    final mgr = ref.read(asrModelManagerProvider);
    try {
      await mgr.ensureAndWarm(model, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      await _save(prefs.copyWith(useOnDeviceModel: model.prefString));
      _snack('${model.label} ready');
    } catch (_) {
      _snack('Couldn’t prepare ${model.label} — keeping current model');
    } finally {
      if (mounted) {
        setState(() {
          _switchingTo = null;
          _progress = 0;
        });
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}
