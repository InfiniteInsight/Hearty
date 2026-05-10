import 'package:drift/drift.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/notification_setup_provider.dart';
import 'core/offline/offline_database.dart';
import 'core/sync/sync_service.dart';

/// WorkManager callback — must be a top-level function.
///
/// Full sync in background requires reconstructing auth + Dio without Riverpod,
/// which is complex and out of scope. Instead, this task cleans up stale
/// 'syncing' rows left by an interrupted foreground sync so they are retried
/// when the app returns to the foreground.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final db = OfflineDatabase();
    try {
      await (db.update(db.offlineQueue)
            ..where((q) => q.status.equals('syncing')))
          .write(const OfflineQueueCompanion(status: Value('pending')));
    } finally {
      await db.close();
    }
    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  assert(supabaseUrl.isNotEmpty,
      'SUPABASE_URL is empty — run with --dart-define-from-file=../.env');
  assert(supabaseAnonKey.isNotEmpty,
      'SUPABASE_ANON_KEY is empty — run with --dart-define-from-file=../.env');
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await Firebase.initializeApp();
  // init() registers the FCM background handler (must be before runApp),
  // creates notification channels, and sets up the foreground message handler.
  await NotificationService.init();
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    kSyncTaskName,
    kSyncTaskTag,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
  runApp(const ProviderScope(child: HeartyApp()));
  // Wire up deep-link routing from notification taps after the widget tree
  // (and GoRouter) is built.
  NotificationService.setupTapHandlers();
}

class HeartyApp extends ConsumerWidget {
  const HeartyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the sync service alive for the lifetime of the app.
    ref.watch(syncServiceProvider);
    // Keep FCM token in sync and schedule daily check-in.
    ref.watch(notificationSetupProvider);
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'Hearty',
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
