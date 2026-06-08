import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // TEMP (Plan B P0 gate): isolate-ASR no-ANR probe. Remove when B1 lands.
          if (kDebugMode)
            ListTile(
              leading: const Icon(Icons.memory, color: Colors.deepPurple),
              title: const Text('▶ ASR isolate probe (dev)'),
              subtitle: const Text('no-ANR gate for the on-device engine'),
              onTap: () => context.push('/isolate-probe'),
            ),
          // TEMP (Whisper/STT spike): on-device candidate benchmark.
          if (kDebugMode)
            ListTile(
              leading: const Icon(Icons.speed, color: Colors.teal),
              title: const Text('▶ Whisper/STT spike (dev)'),
              subtitle: const Text('benchmark on-device STT candidates'),
              onTap: () => context.push('/whisper-spike'),
            ),
          // Account section
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('Account'),
            subtitle: Text(currentUser?.email ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign Out'),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              await GoogleSignIn().signOut();
            },
          ),
          const Divider(),

          // Notifications
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/notifications'),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voice'),
            subtitle: const Text("Hearty's spoken voice"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/voice'),
          ),
          ListTile(
            leading: const Icon(Icons.keyboard_voice_outlined),
            title: const Text('Dictation'),
            subtitle: const Text('Transcription model & auto-submit'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/dictation'),
          ),
          ListTile(
            leading: const Icon(Icons.mic_none_outlined),
            title: const Text('Wake word'),
            subtitle: const Text("'Hey Hearty' hands-free"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/wake-word'),
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('Conversation style'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/conversation'),
          ),
          const Divider(),

          // Health Profile (Phase 5 wires the actual screen)
          ListTile(
            leading: const Icon(Icons.health_and_safety),
            title: const Text('Health Profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/health-profile'),
          ),
          const Divider(),

          // About
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            subtitle: Text('Hearty v1.0.0'),
          ),
        ],
      ),
    );
  }
}
