import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models/user_preferences.dart';
import '../../../core/api/providers/preferences_provider.dart';
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
  late bool _dailyCheckinEnabled;
  late bool _weeklyDigestEnabled;
  late bool _syncAlertsEnabled;
  late bool _wakeWordEnabled;
  late int _nudgeDelay;
  late TimeOfDay _checkinTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _postMealEnabled = widget.prefs.postMealNudgeEnabled;
    _dailyCheckinEnabled = widget.prefs.dailyCheckinEnabled;
    _weeklyDigestEnabled = widget.prefs.weeklyDigestEnabled;
    _syncAlertsEnabled = widget.prefs.syncErrorAlertsEnabled;
    _wakeWordEnabled = widget.prefs.wakeWordEnabled;
    _nudgeDelay = widget.prefs.nudgeDelayMinutes;
    _checkinTime = TimeOfDay(
      hour: widget.prefs.dailyCheckinHour,
      minute: widget.prefs.dailyCheckinMinute,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = widget.prefs.copyWith(
      postMealNudgeEnabled: _postMealEnabled,
      dailyCheckinEnabled: _dailyCheckinEnabled,
      weeklyDigestEnabled: _weeklyDigestEnabled,
      syncErrorAlertsEnabled: _syncAlertsEnabled,
      wakeWordEnabled: _wakeWordEnabled,
      nudgeDelayMinutes: _nudgeDelay,
      dailyCheckinHour: _checkinTime.hour,
      dailyCheckinMinute: _checkinTime.minute,
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

  Future<void> _pickCheckinTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkinTime,
    );
    if (picked != null) setState(() => _checkinTime = picked);
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
        SwitchListTile(
          title: const Text('Post-meal nudge'),
          subtitle: const Text('Follow-up check-in after logging a meal'),
          value: _postMealEnabled,
          onChanged: (v) => setState(() => _postMealEnabled = v),
        ),
        if (_postMealEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Delay'),
                Text('$_nudgeDelay min',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          Slider(
            value: _nudgeDelay.toDouble(),
            min: 30,
            max: 90,
            divisions: 12, // 5-minute steps
            label: '$_nudgeDelay min',
            onChanged: (v) =>
                setState(() => _nudgeDelay = (v / 5).round() * 5),
          ),
        ],
        const Divider(),

        // ── Daily check-in ────────────────────────────────────────────────
        SwitchListTile(
          title: const Text('Daily check-in'),
          subtitle: const Text('Morning wellbeing reminder'),
          value: _dailyCheckinEnabled,
          onChanged: (v) => setState(() => _dailyCheckinEnabled = v),
        ),
        if (_dailyCheckinEnabled)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Check-in time'),
            trailing: Text(
              _checkinTime.format(context),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            onTap: _pickCheckinTime,
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
