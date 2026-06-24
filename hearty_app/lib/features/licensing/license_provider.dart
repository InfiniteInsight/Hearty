import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/hearty_api_client.dart';
import '../../core/auth/auth_repository.dart';

/// Fetches the current user's license status from the backend after auth.
///
/// This is a [FutureProvider] — the async fetch happens inside the provider's
/// body, NOT during any widget build, which satisfies the "never mutate a
/// provider during build" rule (the photo-upload lesson). The router consumes
/// it via `ref.read(...).valueOrNull` and re-evaluates on change.
///
/// Re-runs whenever auth state changes (login/logout). When signed out it
/// returns a neutral `'active'` so we never fire an unauthenticated request
/// (which would 401 → token-refresh failure → forced sign-out loop).
final licenseStatusProvider = FutureProvider<String>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 'active';
  final client = ref.watch(heartyApiClientProvider);
  return client.licenseStatus();
});

/// Pure routing decision for the license gate, extracted so it can be unit
/// tested without standing up Supabase + GoRouter.
///
/// [status] is the resolved license status, or `null` while loading / on a
/// transient fetch error. A `null` status NEVER trips the gate (fail-open,
/// offline-first): the server still enforces the gate on every data request,
/// so a cached/offline phone keeps working and we only block when the server
/// actually reports a non-active status.
///
/// Returns the path to redirect to, or `null` to stay put.
String? licenseRedirect({
  required bool isAuthenticated,
  required String? status,
  required String location,
}) {
  if (!isAuthenticated) return null;

  final isOnNoAccess = location == '/no-access';

  // Loading / transient error → allow through (the API remains the enforcer).
  if (status == null) return null;

  if (status != 'active') {
    return isOnNoAccess ? null : '/no-access';
  }

  // License is active — if we're stuck on the gate, return to the app.
  if (isOnNoAccess) return '/home';
  return null;
}

/// Whether the license gate should run at [location] for an authenticated user.
/// Excludes the pre-account auth/setup screens; INCLUDES `/onboarding` so a gated
/// (paywall/expired) user is routed to `/no-access` before entering onboarding
/// (which would otherwise call gated endpoints and 403).
bool inLicensedArea({required bool isAuthenticated, required String location}) {
  if (!isAuthenticated) return false;
  const exempt = {'/sign-in', '/setup', '/notification-setup', '/conversation-style-setup'};
  return !exempt.contains(location);
}
