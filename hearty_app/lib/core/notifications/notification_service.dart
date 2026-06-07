import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../app/router.dart';

/// Top-level FCM background handler — isolate constraint: must be top-level
/// and marked @pragma so the tree-shaker preserves it.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // The OS automatically displays the notification from FCM data when the app
  // is in the background/terminated, so no extra work is needed here.
}

class NotificationService {
  // 1001 is reserved by HeartyWakeWordService — use a non-colliding range.
  static const _kFollowUpNotifId  = 3010;

  /// Post-meal check-in notification copy. The body tells the user the app will
  /// listen for a spoken reply, so the listen "ding" doesn't catch them off guard.
  static const String followUpTitle = 'How are you feeling?';
  static const String followUpBody =
      "Tap to check in on your last meal — I'll listen for your reply.";

  static final _localNotifs = FlutterLocalNotificationsPlugin();

  /// Call once in main() before runApp, after Firebase.initializeApp().
  static Future<void> init() async {
    // Timezone database needed for scheduled local notifications.
    tz_data.initializeTimeZones();
    final tzName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzName));

    // Register the background message handler (must be before runApp).
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    // One-time migration: IDs 1001–1003 were used before 3001–3003 were
    // introduced to avoid colliding with HeartyWakeWordService (ID 1001).
    // Cancel any lingering scheduled alarms from the old ID range.
    await _localNotifs.cancel(1001);
    await _localNotifs.cancel(1002);
    await _localNotifs.cancel(1003);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifs.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotifTap,
    );

    // Channels are idempotent — safe to call on every cold start.
    await _createChannels();

    // Display FCM messages that arrive while the app is in the foreground.
    FirebaseMessaging.onMessage.listen(_showForegroundMessage);
  }

  /// Wire up notification-tap deep links after the router is ready.
  /// Call once in main() after runApp.
  static void setupTapHandlers() {
    // App launched from terminated state by tapping a notification.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _routeFromMessage(message);
    });

    // App in background, user taps notification.
    FirebaseMessaging.onMessageOpenedApp.listen(_routeFromMessage);
  }

  static Future<void> _createChannels() async {
    final plugin = _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return;

    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'hearty_meal_followup',
      'Meal Follow-Ups',
      importance: Importance.high,
    ));
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'hearty_digest',
      'Weekly Digest',
      importance: Importance.defaultImportance,
    ));
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'hearty_system',
      'Sync & System',
      importance: Importance.low,
    ));
  }

  static Future<void> _showForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final channelId =
        message.data['channel_id'] as String? ?? 'hearty_system';
    await _localNotifs.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(channelId, channelId),
      ),
      payload: message.data['route'] as String?,
    );
  }

  static void _onLocalNotifTap(NotificationResponse response) {
    _navigateTo(response.payload ?? '/home');
  }

  static void _routeFromMessage(RemoteMessage message) {
    _navigateTo(message.data['route'] as String? ?? '/home');
  }

  static void _navigateTo(String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) GoRouter.of(ctx).go(route);
    });
  }

  /// Schedule a one-shot post-meal follow-up notification [delayMinutes] from now.
  /// Replaces any previously pending follow-up so back-to-back meals reset the timer.
  static Future<void> scheduleFollowUpNotification(int delayMinutes) async {
    await _localNotifs.cancel(_kFollowUpNotifId);

    final now = tz.TZDateTime.now(tz.local);
    final scheduled = now.add(Duration(minutes: delayMinutes));

    final androidPlugin = _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final canExact =
        await androidPlugin?.canScheduleExactNotifications() ?? false;

    await _localNotifs.zonedSchedule(
      _kFollowUpNotifId,
      followUpTitle,
      followUpBody,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'hearty_meal_followup',
          'Meal Follow-Ups',
          groupKey: 'hearty_followup_group',
        ),
      ),
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: '/log?followup=true',
    );
  }
}
