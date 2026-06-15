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
  static const int _kCheckinNotifId = 3011; // distinct from follow-up (3010)
  static const int _kTrendsNotifId  = 3012; // monthly trends conversation
  static const int _kExperimentNotifId = 3013; // experiment end-of-window

  /// Post-meal check-in notification copy. The body tells the user the app will
  /// listen for a spoken reply, so the listen "ding" doesn't catch them off guard.
  static const String followUpTitle = 'How are you feeling?';
  static const String followUpBody =
      "Tap to check in on your last meal — I'll listen for your reply.";

  /// Evening daily check-in notification copy.
  static const String checkinTitle = 'Review your day';
  static const String checkinBody  = 'Tap to check in on what you logged today.';

  /// Monthly trends conversation notification copy.
  static const String trendsTitle = 'Your monthly trends';
  static const String trendsBody  =
      "Let's talk through what your data showed this month.";

  /// End-of-window experiment result notification copy.
  static const String experimentTitle = 'Your experiment is done';
  static const String experimentBody  =
      'Tap to see how cutting it back went.';

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
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'hearty_daily_checkin',
      'Daily Check-in',
      importance: Importance.high,
    ));
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'hearty_trends',
      'Monthly Trends',
      importance: Importance.defaultImportance,
    ));
    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      'hearty_experiment',
      'Experiment Results',
      importance: Importance.high,
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

  /// Schedules the evening daily check-in for [hour]:[minute] today (or, if that
  /// time already passed, tomorrow). Day-anchored: the payload carries the target
  /// date so a late tap still reviews the right day. GATE-4 = defer-to-tap: the
  /// /checkin screen runs gap detection on open (silent on clean days because the
  /// screen shows "nothing to review"); we do not pre-detect in the background.
  static Future<void> scheduleCheckinNotification({
    int hour = 20,
    int minute = 0,
  }) async {
    await _localNotifs.cancel(_kCheckinNotifId);

    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (target.isBefore(now)) target = target.add(const Duration(days: 1));

    // Payload date is the reviewed day = the day the notification fires (post
    // day-rollover adjustment above), formatted zero-padded like the router helper.
    final ymd = '${target.year.toString().padLeft(4, '0')}-'
        '${target.month.toString().padLeft(2, '0')}-'
        '${target.day.toString().padLeft(2, '0')}';

    final androidPlugin = _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final canExact =
        await androidPlugin?.canScheduleExactNotifications() ?? false;

    await _localNotifs.zonedSchedule(
      _kCheckinNotifId,
      checkinTitle,
      checkinBody,
      target,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'hearty_daily_checkin',
          'Daily Check-in',
        ),
      ),
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: '/checkin?date=$ymd',
    );
  }

  /// Schedules a recurring monthly trends notification on [dayOfMonth] at
  /// [hour]:[minute]. Recurs via [DateTimeComponents.dayOfMonthAndTime] so it
  /// fires the same day each month. GATE-2 = defer-to-tap: the payload routes
  /// to /trends-conversation, which loads signals on open — there is no
  /// background WorkManager precompute.
  static Future<void> scheduleTrendsNotification({
    int dayOfMonth = 1,
    int hour = 18,
    int minute = 0,
  }) async {
    await _localNotifs.cancel(_kTrendsNotifId);

    final now = tz.TZDateTime.now(tz.local);
    var target =
        tz.TZDateTime(tz.local, now.year, now.month, dayOfMonth, hour, minute);
    // If this month's occurrence already passed, advance to next month so the
    // first fire is in the future (dayOfMonthAndTime then keeps it monthly).
    if (target.isBefore(now)) {
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final nextYear = now.month == 12 ? now.year + 1 : now.year;
      target =
          tz.TZDateTime(tz.local, nextYear, nextMonth, dayOfMonth, hour, minute);
    }

    final androidPlugin = _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final canExact =
        await androidPlugin?.canScheduleExactNotifications() ?? false;

    await _localNotifs.zonedSchedule(
      _kTrendsNotifId,
      trendsTitle,
      trendsBody,
      target,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'hearty_trends',
          'Monthly Trends',
        ),
      ),
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      payload: '/trends-conversation',
    );
  }

  /// Schedules a one-shot end-of-window notification for experiment
  /// [experimentId] at [end]. GATE = defer-to-tap: the payload routes to
  /// /experiment-result, which evaluates the experiment on open — there is no
  /// background WorkManager precompute. Replaces any pending experiment alarm
  /// (one running experiment at a time mirrors the single-slot follow-up timer).
  static Future<void> scheduleExperimentEndNotification({
    required String experimentId,
    required DateTime end,
  }) async {
    await _localNotifs.cancel(_kExperimentNotifId);

    final scheduled = tz.TZDateTime.from(end, tz.local);

    final androidPlugin = _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final canExact =
        await androidPlugin?.canScheduleExactNotifications() ?? false;

    await _localNotifs.zonedSchedule(
      _kExperimentNotifId,
      experimentTitle,
      experimentBody,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'hearty_experiment',
          'Experiment Results',
        ),
      ),
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: '/experiment-result?id=$experimentId',
    );
  }
}
