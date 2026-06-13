import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hearty_api_client.dart';
import '../auth/auth_repository.dart';
import 'notification_service.dart';

/// Keeps FCM token in sync with the API. Watch this in HeartyApp.build
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
});

Future<void> _syncToken(Ref ref) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    final client = ref.read(heartyApiClientProvider);
    final prefs = await client.fetchPreferences();

    // Schedule the evening daily check-in (defer-to-tap). Done BEFORE the
    // fcmToken short-circuit below so it reschedules on every normal launch
    // (token-unchanged is the common case), and in its own try/catch so a
    // scheduling failure can't break token sync and vice-versa.
    try {
      if (prefs.dailyCheckinEnabled) {
        await NotificationService.scheduleCheckinNotification(
          hour: prefs.dailyCheckinHour,
          minute: prefs.dailyCheckinMinute,
        );
      }
    } catch (_) {
      // Best-effort — never block token sync or startup.
    }

    if (prefs.fcmToken == token) return;
    await client.savePreferences(prefs.copyWith(fcmToken: token));
  } catch (_) {
    // Best-effort — will retry on next launch or token refresh.
  }
}
