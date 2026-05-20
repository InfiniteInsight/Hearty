import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models/user_preferences.dart';
import '../../../core/api/models/wellbeing_period.dart';
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/notifications/notification_service.dart';
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
  // Per-slot check-in state
  late bool _morningEnabled;
  late TimeOfDay _morningTime;
  late bool _middayEnabled;
  late TimeOfDay _middayTime;
  late bool _eveningEnabled;
  late TimeOfDay _eveningTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _postMealEnabled = widget.prefs.postMealNudgeEnabled;
    _weeklyDigestEnabled = widget.prefs.weeklyDigestEnabled;
    _syncAlertsEnabled = widget.prefs.syncErrorAlertsEnabled;
    _wakeWordEnabled = widget.prefs.wakeWordEnabled;
    _nudgeDelay = widget.prefs.nudgeDelayMinutes;
    _morningEnabled = widget.prefs.morningCheckinEnabled;
    _morningTime = TimeOfDay(
        hour: widget.prefs.morningCheckinHour,
        minute: widget.prefs.morningCheckinMinute);
    _middayEnabled = widget.prefs.middayCheckinEnabled;
    _middayTime = TimeOfDay(
        hour: widget.prefs.middayCheckinHour,
        minute: widget.prefs.middayCheckinMinute);
    _eveningEnabled = widget.prefs.eveningCheckinEnabled;
    _eveningTime = TimeOfDay(
        hour: widget.prefs.eveningCheckinHour,
        minute: widget.prefs.eveningCheckinMinute);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = widget.prefs.copyWith(
      postMealNudgeEnabled: _postMealEnabled,
      weeklyDigestEnabled: _weeklyDigestEnabled,
      syncErrorAlertsEnabled: _syncAlertsEnabled,
      wakeWordEnabled: _wakeWordEnabled,
      nudgeDelayMinutes: _nudgeDelay,
      morningCheckinEnabled: _morningEnabled,
      morningCheckinHour: _morningTime.hour,
      morningCheckinMinute: _morningTime.minute,
      middayCheckinEnabled: _middayEnabled,
      middayCheckinHour: _middayTime.hour,
      middayCheckinMinute: _middayTime.minute,
      eveningCheckinEnabled: _eveningEnabled,
      eveningCheckinHour: _eveningTime.hour,
      eveningCheckinMinute: _eveningTime.minute,
    );
    await ref.read(preferencesProvider.notifier).save(updated);
    // Reschedule all three notifications immediately.
    _rescheduleAll(updated);
    if (!mounted) return;
    final result = ref.read(preferencesProvider);
    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save — please try again')),
      );
    }
    setState(() => _saving = false);
  }

  void _rescheduleAll(UserPreferences prefs) {
    NotificationService.scheduleCheckinNotification(
      period: WellbeingPeriod.morning,
      hour: prefs.morningCheckinHour,
      minute: prefs.morningCheckinMinute,
      enabled: prefs.morningCheckinEnabled,
    );
    NotificationService.scheduleCheckinNotification(
      period: WellbeingPeriod.midday,
      hour: prefs.middayCheckinHour,
      minute: prefs.middayCheckinMinute,
      enabled: prefs.middayCheckinEnabled,
    );
    NotificationService.scheduleCheckinNotification(
      period: WellbeingPeriod.evening,
      hour: prefs.eveningCheckinHour,
      minute: prefs.eveningCheckinMinute,
      enabled: prefs.eveningCheckinEnabled,
    );
  }

  Future<void> _pickTime(
    TimeOfDay current,
    ValueChanged<TimeOfDay> onPicked,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked != null) onPicked(picked);
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
            min: 5,
            max: 90,
            divisions: 17,
            label: '$_nudgeDelay min',
            onChanged: (v) =>
                setState(() => _nudgeDelay = (v / 5).round() * 5),
          ),
        ],
        const Divider(),

        // ── Check-in notifications ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Check-in reminders',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        _CheckinRow(
          label: 'Morning check-in',
          enabled: _morningEnabled,
          time: _morningTime,
          onToggle: (v) => setState(() => _morningEnabled = v),
          onTimeTap: () => _pickTime(
              _morningTime, (t) => setState(() => _morningTime = t)),
        ),
        _CheckinRow(
          label: 'Midday check-in',
          enabled: _middayEnabled,
          time: _middayTime,
          onToggle: (v) => setState(() => _middayEnabled = v),
          onTimeTap: () =>
              _pickTime(_middayTime, (t) => setState(() => _middayTime = t)),
        ),
        _CheckinRow(
          label: 'Evening check-in',
          enabled: _eveningEnabled,
          time: _eveningTime,
          onToggle: (v) => setState(() => _eveningEnabled = v),
          onTimeTap: () => _pickTime(
              _eveningTime, (t) => setState(() => _eveningTime = t)),
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
              "Say 'Hey Jarvis' to open the voice overlay hands-free"),
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

class _CheckinRow extends StatelessWidget {
  final String label;
  final bool enabled;
  final TimeOfDay time;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTimeTap;

  const _CheckinRow({
    required this.label,
    required this.enabled,
    required this.time,
    required this.onToggle,
    required this.onTimeTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (enabled)
            GestureDetector(
              onTap: onTimeTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  time.format(context),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ),
          Switch(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}
