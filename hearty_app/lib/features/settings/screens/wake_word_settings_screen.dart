import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Wake Word')),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load preferences: $e')),
        data: (prefs) => ListView(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.mic_none_outlined),
              title: const Text('Wake word detection'),
              subtitle: const Text(
                  "Say 'Hey Hearty' to open the voice overlay hands-free"),
              value: prefs.wakeWordEnabled,
              onChanged: (enabled) async {
                // Start/stop the foreground service so the persistent
                // notification appears or disappears immediately. (Distinct
                // from the notification's Pause/Resume, which only suspends
                // detection without stopping the service.)
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'When on, Hearty listens in the background for the wake phrase. '
                'A persistent notification shows while detection is active.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
