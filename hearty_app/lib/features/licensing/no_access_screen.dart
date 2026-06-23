import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'license_provider.dart';

/// Non-dismissable gated state shown when the server reports that the user has
/// no active license. The user can re-check (after the owner re-grants access)
/// or sign out (which fires an auth state change → the router redirects to
/// /sign-in).
class NoAccessScreen extends ConsumerWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-fetching the status re-fires the router's listener; if the owner has
    // re-granted access, the redirect routes back to home — no restart needed.
    final checking = ref.watch(licenseStatusProvider).isLoading;
    // canPop: false traps the system back button; GoRouter redirect traps any
    // programmatic navigation away while the license is non-active.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'No active access',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your account does not have an active license. '
                    'Please contact the owner to regain access.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: checking
                        ? null
                        : () => ref.invalidate(licenseStatusProvider),
                    child: Text(checking ? 'Checking…' : 'Check again'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      await Supabase.instance.client.auth.signOut();
                      await GoogleSignIn().signOut();
                    },
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
