import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models/user_preferences.dart';
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/widgets/post_meal_nudge_section.dart';
import '../../../features/wake_word/wake_word_channel.dart';

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(preferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load preferences: $e')),
        data: (prefs) => _PreferencesForm(prefs: prefs),
      ),
    );
  }
}

class _PreferencesForm extends ConsumerStatefulWidget {
  final UserPreferences prefs;
  const _PreferencesForm({required this.prefs});

  @override
  ConsumerState<_PreferencesForm> createState() => _PreferencesFormState();
}

class _PreferencesFormState extends ConsumerState<_PreferencesForm> {
  late bool _postMealEnabled;
  late bool _weeklyDigestEnabled;
  late bool _syncAlertsEnabled;
  late bool _wakeWordEnabled;
  late int _nudgeDelay;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _postMealEnabled = widget.prefs.postMealNudgeEnabled;
    _weeklyDigestEnabled = widget.prefs.weeklyDigestEnabled;
    _syncAlertsEnabled = widget.prefs.syncErrorAlertsEnabled;
    _wakeWordEnabled = widget.prefs.wakeWordEnabled;
    _nudgeDelay = widget.prefs.nudgeDelayMinutes;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = widget.prefs.copyWith(
      postMealNudgeEnabled: _postMealEnabled,
      weeklyDigestEnabled: _weeklyDigestEnabled,
      syncErrorAlertsEnabled: _syncAlertsEnabled,
      wakeWordEnabled: _wakeWordEnabled,
      nudgeDelayMinutes: _nudgeDelay,
    );
    await ref.read(preferencesProvider.notifier).save(updated);
    if (!mounted) return;
    final result = ref.read(preferencesProvider);
    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save — please try again')),
      );
    }
    setState(() => _saving = false);
  }

  void _toggleWakeWord(bool enabled) {
    setState(() => _wakeWordEnabled = enabled);
    if (enabled) {
      WakeWordChannel.startListening().catchError((_) {});
    } else {
      WakeWordChannel.stopListening().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // ── Post-meal nudge ───────────────────────────────────────────────
        PostMealNudgeSection(
          enabled: _postMealEnabled,
          delayMinutes: _nudgeDelay,
          onToggle: (v) => setState(() => _postMealEnabled = v),
          onDelayChanged: (v) => setState(() => _nudgeDelay = v),
        ),
        const Divider(),

        // ── Weekly digest ─────────────────────────────────────────────────
        SwitchListTile(
          title: const Text('Weekly digest'),
          subtitle: const Text('Sunday summary of your week'),
          value: _weeklyDigestEnabled,
          onChanged: (v) => setState(() => _weeklyDigestEnabled = v),
        ),
        const Divider(),

        // ── Sync error alerts ─────────────────────────────────────────────
        SwitchListTile(
          title: const Text('Sync error alerts'),
          subtitle: const Text('Notify if logs fail to upload'),
          value: _syncAlertsEnabled,
          onChanged: (v) => setState(() => _syncAlertsEnabled = v),
        ),
        const Divider(),

        // ── Wake word ─────────────────────────────────────────────────────
        SwitchListTile(
          title: const Text('Wake word detection'),
          subtitle: const Text(
              "Say 'Hey Hearty' to open the voice overlay hands-free"),
          value: _wakeWordEnabled,
          onChanged: _toggleWakeWord,
        ),
        const Divider(),

        // ── Save button ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ),
      ],
    );
  }
}
