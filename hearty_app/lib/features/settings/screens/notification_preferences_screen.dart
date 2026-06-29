import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../../../core/api/models/user_preferences.dart';
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/widgets/post_meal_nudge_section.dart';

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(preferencesProvider);

    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('Notifications')),
          body: prefsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Failed to load preferences: $e')),
            data: (prefs) => _PreferencesForm(prefs: prefs),
          ),
        ),
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
  late int _nudgeDelay;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _postMealEnabled = widget.prefs.postMealNudgeEnabled;
    _weeklyDigestEnabled = widget.prefs.weeklyDigestEnabled;
    _syncAlertsEnabled = widget.prefs.syncErrorAlertsEnabled;
    _nudgeDelay = widget.prefs.nudgeDelayMinutes;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updated = widget.prefs.copyWith(
      postMealNudgeEnabled: _postMealEnabled,
      weeklyDigestEnabled: _weeklyDigestEnabled,
      syncErrorAlertsEnabled: _syncAlertsEnabled,
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

  /// Aurora glass card wrapping a group of settings rows.
  Widget _glassCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Aurora.glassFill,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Aurora.glassBorder),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // ── Post-meal nudge ───────────────────────────────────────────────
        _glassCard(
          child: PostMealNudgeSection(
            enabled: _postMealEnabled,
            delayMinutes: _nudgeDelay,
            onToggle: (v) => setState(() => _postMealEnabled = v),
            onDelayChanged: (v) => setState(() => _nudgeDelay = v),
          ),
        ),

        // ── Weekly digest ─────────────────────────────────────────────────
        _glassCard(
          child: SwitchListTile(
            title: const Text('Weekly digest',
                style: TextStyle(color: Aurora.textPrimary)),
            subtitle: const Text('Sunday summary of your week',
                style: TextStyle(color: Aurora.textSecondary)),
            activeThumbColor: Aurora.accentGreen,
            value: _weeklyDigestEnabled,
            onChanged: (v) => setState(() => _weeklyDigestEnabled = v),
          ),
        ),

        // ── Sync error alerts ─────────────────────────────────────────────
        _glassCard(
          child: SwitchListTile(
            title: const Text('Sync error alerts',
                style: TextStyle(color: Aurora.textPrimary)),
            subtitle: const Text('Notify if logs fail to upload',
                style: TextStyle(color: Aurora.textSecondary)),
            activeThumbColor: Aurora.accentGreen,
            value: _syncAlertsEnabled,
            onChanged: (v) => setState(() => _syncAlertsEnabled = v),
          ),
        ),

        // ── Save button ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Aurora.accentGreen,
              foregroundColor: const Color(0xFF052E20),
            ),
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
