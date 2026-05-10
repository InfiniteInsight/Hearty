import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hearty_api_client.dart';
import '../api/providers/preferences_provider.dart';
import '../auth/auth_repository.dart';
import 'notification_service.dart';

/// Keeps FCM token in sync with the API and auto-schedules the daily
/// check-in whenever preferences change. Watch this in HeartyApp.build
/// to keep it alive for the lifetime of the app.
final notificationSetupProvider = Provider<void>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;

  // Initial token sync (fire-and-forget).
  Future.microtask(() => _syncToken(ref));

  // Re-sync whenever the token rotates (reinstall, data clear, etc.).
  final sub = FirebaseMessaging.instance.onTokenRefresh
      .listen((_) => Future.microtask(() => _syncToken(ref)));
  ref.onDispose(sub.cancel);

  // Schedule / cancel daily check-in whenever preferences change.
  ref.listen(preferencesProvider, (_, next) {
    next.whenData((prefs) {
      if (prefs.dailyCheckinEnabled) {
        NotificationService.scheduleDailyCheckin(
          prefs.dailyCheckinHour,
          prefs.dailyCheckinMinute,
        );
      } else {
        NotificationService.cancelDailyCheckin();
      }
    });
  });
});

Future<void> _syncToken(Ref ref) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    final client = ref.read(heartyApiClientProvider);
    final prefs = await client.fetchPreferences();
    if (prefs.fcmToken == token) return;
    await client.savePreferences(prefs.copyWith(fcmToken: token));
  } catch (_) {
    // Best-effort — will retry on next launch or token refresh.
  }
}
