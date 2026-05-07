import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

/// Checks whether the current user has a row in the `user_profiles` table,
/// which indicates completed onboarding.
///
/// Returns false when: not authenticated, no row found, or any error occurs.
final hasCompletedOnboardingProvider = FutureProvider<bool>((ref) async {
  // Re-evaluate whenever auth state changes.
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;

  try {
    final result = await Supabase.instance.client
        .from('user_profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    return result != null;
  } catch (_) {
    return false;
  }
});
