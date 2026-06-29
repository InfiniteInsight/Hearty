import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../../../core/api/providers/preferences_provider.dart';
import '../../../features/wake_word/wake_word_channel.dart';

/// Dedicated Settings page for the "Hey Hearty" wake word. Auto-saves on
/// toggle (consistent with the Voice settings page) and starts/stops the
/// foreground detection service immediately.
class WakeWordSettingsScreen extends ConsumerWidget {
  const WakeWordSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(preferencesProvider);

    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('Wake Word')),
          body: prefsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Failed to load preferences: $e')),
            data: (prefs) => ListView(
              children: [
                // Wake word detection toggle — grouped in an Aurora glass card.
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Aurora.glassFill,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Aurora.glassBorder),
                  ),
                  child: SwitchListTile(
                    secondary: const Icon(Icons.mic_none_outlined,
                        color: Aurora.textSecondary),
                    title: const Text('Wake word detection',
                        style: TextStyle(color: Aurora.textPrimary)),
                    subtitle: const Text(
                      "Say 'Hey Hearty' to open the voice overlay hands-free",
                      style: TextStyle(color: Aurora.textSecondary),
                    ),
                    activeThumbColor: Aurora.accentGreen,
                    value: prefs.wakeWordEnabled,
                    onChanged: (enabled) async {
                      // Start/stop the foreground service so the persistent
                      // notification appears or disappears immediately.
                      // (Distinct from the notification's Pause/Resume, which
                      // only suspends detection without stopping the service.)
                      if (enabled) {
                        WakeWordChannel.startService().catchError((_) {});
                      } else {
                        WakeWordChannel.stopService().catchError((_) {});
                      }
                      await ref
                          .read(preferencesProvider.notifier)
                          .save(prefs.copyWith(wakeWordEnabled: enabled));
                      // Mirror to local SharedPreferences so BootReceiver and
                      // MainActivity can gate service startup without a Supabase
                      // round-trip.
                      final localPrefs = await SharedPreferences.getInstance();
                      await localPrefs.setBool('wake_word_enabled', enabled);
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'When on, Hearty listens in the background for the wake phrase. '
                    'A persistent notification shows while detection is active.',
                    style: TextStyle(fontSize: 12, color: Aurora.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
