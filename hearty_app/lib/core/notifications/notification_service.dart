import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../app/router.dart';
import '../api/models/wellbeing_period.dart';

/// Top-level FCM background handler — isolate constraint: must be top-level
/// and marked @pragma so the tree-shaker preserves it.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // The OS automatically displays the notification from FCM data when the app
  // is in the background/terminated, so no extra work is needed here.
}

class NotificationService {
  static const _kCheckinNotifId = 1001;

  static final _localNotifs = FlutterLocalNotificationsPlugin();

  /// Call once in main() before runApp, after Firebase.initializeApp().
  static Future<void> init() async {
    // Timezone database needed for scheduled local notifications.
    tz_data.initializeTimeZones();
    final tzName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzName));

    // Register the background message handler (must be before runApp).
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

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
      'hearty_daily_checkin',
      'Daily Check-In',
      importance: Importance.defaultImportance,
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

  static int _notifId(WellbeingPeriod period) => switch (period) {
        WellbeingPeriod.morning => 1001,
        WellbeingPeriod.midday => 1002,
        WellbeingPeriod.evening => 1003,
      };

  static String _notifTitle(WellbeingPeriod period) => switch (period) {
        WellbeingPeriod.morning => 'Good morning — how are you feeling?',
        WellbeingPeriod.midday => 'Midday check-in',
        WellbeingPeriod.evening => 'Evening check-in',
      };

  /// Schedule (or cancel) a single period check-in notification.
  static Future<void> scheduleCheckinNotification({
    required WellbeingPeriod period,
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    final id = _notifId(period);
    await _localNotifs.cancel(id);
    if (!enabled) return;

    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    final androidPlugin = _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final canExact =
        await androidPlugin?.canScheduleExactNotifications() ?? false;

    await _localNotifs.zonedSchedule(
      id,
      _notifTitle(period),
      'Tap to log your ${period.name} wellbeing.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'hearty_daily_checkin',
          'Daily Check-In',
        ),
      ),
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: '/wellbeing/log?period=${period.name}',
    );
  }

  /// Schedule (or reschedule) the daily check-in local notification.
  /// Kept for backward compatibility — delegates to scheduleCheckinNotification.
  static Future<void> scheduleDailyCheckin(int hour, int minute) async {
    await scheduleCheckinNotification(
      period: WellbeingPeriod.morning,
      hour: hour,
      minute: minute,
      enabled: true,
    );
  }

  static Future<void> cancelDailyCheckin() async {
    await _localNotifs.cancel(_kCheckinNotifId);
  }
}
