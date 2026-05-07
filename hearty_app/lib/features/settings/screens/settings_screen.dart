import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_repository.dart';
import '../providers/default_assistant_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final defaultAssistant = ref.watch(defaultAssistantProvider);

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

          // Default Assistant
          const ListTile(
            title: Text(
              'Default Assistant',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Where non-health queries are redirected'),
          ),
          ...DefaultAssistant.values.map(
            (assistant) => RadioListTile<DefaultAssistant>(
              title: Text(assistant.label),
              value: assistant,
              // ignore: deprecated_member_use
              groupValue: defaultAssistant,
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) {
                  ref.read(defaultAssistantProvider.notifier).state = value;
                }
              },
            ),
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
