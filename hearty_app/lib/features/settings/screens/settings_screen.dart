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
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/voice'),
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
