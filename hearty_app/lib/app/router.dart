import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:permission_handler/permission_handler.dart';

import '../core/audio/chime_player.dart';
import '../core/auth/onboarding_provider.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/voice/providers/voice_provider.dart';
import '../features/voice/screens/voice_overlay_screen.dart';
import '../features/wake_word/providers/wake_word_provider.dart';
import '../features/wake_word/wake_word_channel.dart';
import '../features/logging/screens/home_screen.dart';
import '../features/history/screens/history_screen.dart';
import '../features/trends/screens/trends_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/logging/screens/log_entry_screen.dart';
import '../features/health_profile/screens/health_profile_screen.dart';
import '../features/logging/screens/log_detail_screen.dart';
import '../features/logging/screens/onboarding_screen.dart';
import '../features/photos/screens/camera_screen.dart';
import '../features/settings/screens/notification_preferences_screen.dart';
import '../features/settings/screens/voice_settings_screen.dart';
import '../features/logging/screens/edit_meal_screen.dart';
import '../features/logging/screens/edit_symptom_screen.dart';
import '../features/wellbeing/screens/wellbeing_log_screen.dart';
import '../features/setup/screens/setup_screen.dart';
import '../features/setup/screens/notification_setup_screen.dart';
import '../core/api/models/wellbeing_period.dart';
import '../core/api/providers/last_logged_provider.dart';
import '../core/api/providers/meals_provider.dart';
import '../core/api/providers/symptoms_provider.dart';
import '../core/api/providers/wellbeing_provider.dart';

/// Global navigator key — used by [NotificationService] to push deep links
/// when a notification is tapped from background/terminated state.
final navigatorKey = GlobalKey<NavigatorState>();

class Routes {
  static const String home = 'home';
  static const String history = 'history';
  static const String trends = 'trends';
  static const String settings = 'settings';
  static const String log = 'log';
  static const String logDetail = 'log-detail';
  static const String healthProfile = 'health-profile';
  static const String onboarding = 'onboarding';
  static const String signIn = 'sign-in';
  static const String camera = 'camera';
  static const String notificationPreferences = 'notification-preferences';
  static const String voiceSettings = 'voice-settings';
  static const String wellbeingLog = 'wellbeing-log';
  static const String editMeal = 'edit-meal';
  static const String editSymptom = 'edit-symptom';
  static const String setup = 'setup';
  static const String notificationSetup = 'notification-setup';
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshStream = GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  );

  // When the onboarding flag changes, trigger the router to re-evaluate its
  // redirect without rebuilding the provider (ref.listen, not ref.watch).
  ref.listen(hasCompletedOnboardingProvider, (_, next) {
    refreshStream.notify();
  }, fireImmediately: false);

  final router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/setup',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuthenticated = session != null;
      final location = state.matchedLocation;
      final isOnSignIn = location == '/sign-in';
      final isOnOnboarding = location == '/onboarding';
      final hasCompletedOnboarding =
          ref.read(hasCompletedOnboardingProvider).valueOrNull ?? false;

      final isOnSetup = location == '/setup';
      final isOnNotificationSetup = location == '/notification-setup';
      if (!isAuthenticated && !isOnSignIn && !isOnSetup && !isOnNotificationSetup) {
        return '/sign-in';
      }
      if (isAuthenticated && isOnSignIn) {
        return hasCompletedOnboarding ? '/home' : '/onboarding';
      }
      if (isAuthenticated && isOnOnboarding && hasCompletedOnboarding) {
        return '/home';
      }
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _ScaffoldWithNavBar(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: Routes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                name: Routes.history,
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/trends',
                name: Routes.trends,
                builder: (context, state) => const TrendsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: Routes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/sign-in',
        name: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/log',
        name: Routes.log,
        builder: (context, state) => const LogEntryScreen(),
      ),
      GoRoute(
        path: '/log/:id',
        name: Routes.logDetail,
        builder: (context, state) =>
            LogDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/health-profile',
        name: Routes.healthProfile,
        builder: (context, state) => const HealthProfileScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/camera',
        name: Routes.camera,
        builder: (context, state) => const CameraScreen(),
      ),
      GoRoute(
        path: '/settings/notifications',
        name: Routes.notificationPreferences,
        builder: (context, state) => const NotificationPreferencesScreen(),
      ),
      GoRoute(
        path: '/settings/voice',
        name: Routes.voiceSettings,
        builder: (context, state) => const VoiceSettingsScreen(),
      ),
      GoRoute(
        path: '/meals/edit',
        name: Routes.editMeal,
        builder: (context, state) {
          final extra = state.extra as Map<String, String>;
          return EditMealScreen(
            id: extra['id']!,
            initialDescription: extra['description']!,
          );
        },
      ),
      GoRoute(
        path: '/symptoms/edit',
        name: Routes.editSymptom,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EditSymptomScreen(
            id: extra['id'] as String,
            initialDescription: extra['description'] as String,
            initialSeverity: extra['severity'] as int?,
            initialOnsetMinutes: extra['onsetMinutes'] as int?,
          );
        },
      ),
      GoRoute(
        path: '/wellbeing/log',
        name: Routes.wellbeingLog,
        builder: (context, state) {
          final periodStr = state.uri.queryParameters['period'];
          final period = switch (periodStr) {
            'morning' => WellbeingPeriod.morning,
            'midday' => WellbeingPeriod.midday,
            'evening' => WellbeingPeriod.evening,
            _ => null,
          };
          final id = state.uri.queryParameters['id'];
          return WellbeingLogScreen(initialPeriod: period, entryId: id);
        },
      ),
      GoRoute(
        path: '/setup',
        name: Routes.setup,
        builder: (context, state) => const SetupScreen(),
      ),
      GoRoute(
        path: '/notification-setup',
        name: Routes.notificationSetup,
        builder: (context, state) => const NotificationSetupScreen(),
      ),
    ],
  );

  // Dispose both the stream bridge and the router when the provider is disposed.
  ref.onDispose(() {
    refreshStream.dispose();
    router.dispose();
  });

  return router;
});

/// Bridges a [Stream] to [ChangeNotifier] so GoRouter re-evaluates its
/// redirect whenever the auth state changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  /// Allows external callers to manually trigger a router redirect re-evaluation.
  void notify() => notifyListeners();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class _ScaffoldWithNavBar extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const _ScaffoldWithNavBar({required this.navigationShell});

  @override
  ConsumerState<_ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends ConsumerState<_ScaffoldWithNavBar> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWakeWord());
  }

  Future<void> _initWakeWord() async {
    final micGranted = await Permission.microphone.isGranted;
    if (micGranted) WakeWordChannel.startService().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    // Global wake-word listener — active on every tab, not just Home.
    ref.listen(wakeWordDetectedProvider, (_, detected) async {
      if (!detected) return;
      await ChimePlayer.instance.play();
      if (!context.mounted) return;
      ref.read(voiceProvider.notifier).startListening();
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const VoiceOverlayScreen(),
      );
      // Show edit shortcut if a meal was just logged.
      final loggedMealId = ref.read(lastLoggedMealIdProvider);
      if (loggedMealId != null && context.mounted) {
        ref.read(lastLoggedMealIdProvider.notifier).state = null;
        // Look up the description so EditMealScreen can pre-populate it.
        final meals = ref.read(mealsProvider).valueOrNull ?? [];
        final meal = meals.where((m) => m.id == loggedMealId).firstOrNull;
        final description = meal?.description ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Logged! Want to add more detail?'),
            action: SnackBarAction(
              label: 'Edit',
              onPressed: () {
                if (context.mounted) {
                  context.push(
                    '/meals/edit',
                    extra: {'id': loggedMealId, 'description': description},
                  );
                }
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      // Refresh timeline so newly logged entries appear immediately.
      ref.invalidate(mealsProvider);
      ref.invalidate(symptomsProvider);
      ref.invalidate(wellbeingProvider);
      ref.read(wakeWordDetectedProvider.notifier).setDetected(false);
      WakeWordChannel.startListening().catchError((_) {});
    });

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (index) => widget.navigationShell.goBranch(
          index,
          initialLocation: index == widget.navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: 'Trends',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
