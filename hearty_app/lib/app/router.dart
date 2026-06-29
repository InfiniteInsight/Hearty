import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';
import 'theme/aurora_colors.dart';
import '../core/auth/onboarding_provider.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/licensing/license_provider.dart';
import '../features/licensing/no_access_screen.dart';
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
import '../features/settings/screens/dictation_settings_screen.dart';
import '../features/settings/screens/wake_word_settings_screen.dart';
import '../features/settings/screens/conversation_style_screen.dart';
import '../features/logging/screens/edit_meal_screen.dart';
import '../features/logging/screens/edit_symptom_screen.dart';
import '../features/setup/screens/setup_screen.dart';
import '../features/checkin/screens/daily_checkin_screen.dart';
import '../features/trends/screens/trends_conversation_screen.dart';
import '../features/setup/screens/notification_setup_screen.dart';
import '../features/setup/screens/conversation_style_setup_screen.dart';
import '../features/experiments/screens/experiment_result_screen.dart';
import '../core/api/providers/preferences_provider.dart';
import '../core/api/models/user_preferences.dart';
import '../core/stt/on_device_model.dart';
import '../core/api/providers/last_logged_provider.dart';
import '../core/api/providers/meals_provider.dart';
import '../core/api/providers/symptoms_provider.dart';

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
  static const String dictationSettings = 'dictation-settings';
  static const String wakeWordSettings = 'wake-word-settings';
  static const String editMeal = 'edit-meal';
  static const String editSymptom = 'edit-symptom';
  static const String setup = 'setup';
  static const String notificationSetup = 'notification-setup';
  static const String conversationStyleSetup = 'conversation-style-setup';
  static const String conversationStyle = 'conversation-style';
  static const String checkin = 'checkin';
  static const String trendsConversation = 'trends-conversation';
  static const String experimentResult = 'experiment-result';
  static const String noAccess = 'no-access';
}

/// Today as `YYYY-MM-DD` in local time — the default reviewed day for /checkin
/// when no `?date=` query param is supplied.
String _todayYmd() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
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

  // Re-evaluate the redirect whenever the license status resolves/changes so a
  // revoke routes to the gate and a re-grant routes back into the app.
  ref.listen(licenseStatusProvider, (_, next) {
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
      final isOnConversationStyleSetup = location == '/conversation-style-setup';
      if (!isAuthenticated && !isOnSignIn && !isOnSetup && !isOnNotificationSetup && !isOnConversationStyleSetup) {
        return '/sign-in';
      }
      if (isAuthenticated && isOnSignIn) {
        return hasCompletedOnboarding ? '/home' : '/onboarding';
      }
      if (isAuthenticated && isOnOnboarding && hasCompletedOnboarding) {
        return '/home';
      }

      // License gate applies to any authenticated user in the app area (incl.
      // /onboarding), so a gated user lands on /no-access instead of 403ing
      // through onboarding. Active users pass straight through.
      if (inLicensedArea(isAuthenticated: isAuthenticated, location: location)) {
        final licenseStatus = ref.read(licenseStatusProvider).valueOrNull;
        final licenseTarget = licenseRedirect(
          isAuthenticated: isAuthenticated,
          status: licenseStatus,
          location: location,
        );
        if (licenseTarget != null) {
          // A newly-activated user still mid-signup (e.g. paywall→granted while
          // waiting on /no-access) would otherwise land on /home un-onboarded.
          // Route them through onboarding first.
          if (licenseTarget == '/home' && !hasCompletedOnboarding) return '/onboarding';
          return licenseTarget;
        }
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
        path: '/no-access',
        name: Routes.noAccess,
        builder: (context, state) => const NoAccessScreen(),
      ),
      GoRoute(
        path: '/log',
        name: Routes.log,
        builder: (context, state) => LogEntryScreen(
          isFollowUp: state.uri.queryParameters['followup'] == 'true',
        ),
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
        path: '/settings/dictation',
        name: Routes.dictationSettings,
        builder: (context, state) => const DictationSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/wake-word',
        name: Routes.wakeWordSettings,
        builder: (context, state) => const WakeWordSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/conversation',
        name: Routes.conversationStyle,
        builder: (context, state) => const ConversationStyleScreen(),
      ),
      GoRoute(
        path: '/meals/edit',
        name: Routes.editMeal,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EditMealScreen(
            id: extra['id'] as String,
            initialDescription: extra['description'] as String,
            initialFoods:
                (extra['foods'] as List?)?.map((e) => e.toString()).toList() ??
                    const <String>[],
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
        path: '/checkin',
        name: Routes.checkin,
        builder: (context, state) => DailyCheckinScreen(
          date: state.uri.queryParameters['date'] ?? _todayYmd(),
        ),
      ),
      GoRoute(
        path: '/trends-conversation',
        name: Routes.trendsConversation,
        builder: (context, state) => const TrendsConversationScreen(),
      ),
      GoRoute(
        path: '/experiment-result',
        name: Routes.experimentResult,
        builder: (context, state) => ExperimentResultScreen(
          experimentId: state.uri.queryParameters['id'] ?? '',
        ),
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
      GoRoute(
        path: '/conversation-style-setup',
        name: Routes.conversationStyleSetup,
        builder: (context, state) => const ConversationStyleSetupScreen(),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWakeWord();
      _prewarmDictation();
    });
  }

  Future<void> _initWakeWord() async {
    final micGranted = await Permission.microphone.isGranted;
    if (!micGranted) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('wake_word_enabled') ?? true) {
      WakeWordChannel.startService().catchError((_) {});
    }
  }

  /// Plan D decision #5: download + warm the selected on-device STT model in the
  /// background after launch, so the FIRST voice interaction isn't silently
  /// degraded to manual while a 275 MB download runs with no UX. Fire-and-forget
  /// — the capture path's own `ensureAndWarm` coalesces with this via the
  /// manager's in-flight guard, and the warm isolate self-releases after 3 min
  /// idle. Gated on mic permission (no point fetching STT if they can't dictate)
  /// and skipped for cloud users. (RAM survival alongside the wake-word service
  /// is verified on device in D5.)
  Future<void> _prewarmDictation() async {
    if (!await Permission.microphone.isGranted) {
      if (kDebugMode) debugPrint('[asr] preload skipped: mic not granted');
      return;
    }
    if (!mounted) return;
    final UserPreferences prefs;
    try {
      prefs = await ref.read(preferencesProvider.future);
    } catch (e) {
      if (kDebugMode) debugPrint('[asr] preload skipped: prefs threw ($e)');
      return;
    }
    if (!mounted) return;
    if (prefs.useCloudWhenOnline) {
      if (kDebugMode) debugPrint('[asr] preload skipped: cloud-when-online on');
      return;
    }
    final model = OnDeviceModel.fromPrefString(prefs.useOnDeviceModel);
    if (kDebugMode) debugPrint('[asr] preload firing for ${model.spec.dir}');
    ref.read(asrModelManagerProvider).ensureAndWarm(model).catchError((e) {
      if (kDebugMode) debugPrint('[asr] preload ensureAndWarm failed: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Global wake-word listener — active on every tab, not just Home.
    ref.listen(wakeWordDetectedProvider, (_, detected) async {
      if (!detected) return;
      if (!context.mounted) return;
      // Capture before the async gap — context-dependent lookups after an
      // await can return a stale or detached instance.
      final messenger = ScaffoldMessenger.of(context);
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
        messenger.clearSnackBars();
        const snackDuration = Duration(seconds: 6);
        final ctrl = messenger.showSnackBar(
          SnackBar(
            content: const Text('Logged! Want to add more detail?'),
            action: SnackBarAction(
              label: 'Edit',
              onPressed: () {
                if (context.mounted) {
                  context.push(
                    '/meals/edit',
                    extra: {
                      'id': loggedMealId,
                      'description': description,
                      'foods': meal?.foods ?? const <String>[],
                    },
                  );
                }
              },
            ),
            duration: snackDuration,
          ),
        );
        // The built-in `duration` auto-dismiss did not fire on-device (the bar
        // lingered indefinitely), so arm our own dismissal as a guarantee.
        Future.delayed(snackDuration, () {
          if (mounted) ctrl.close();
        });
      }
      // Refresh timeline so newly logged entries appear immediately.
      ref.invalidate(mealsProvider);
      ref.invalidate(symptomsProvider);
      ref.read(wakeWordDetectedProvider.notifier).setDetected(false);
      // Re-arm now happens centrally in VoiceOverlayScreen.dispose() (covers
      // every STT entry path, not just wake word), so we no longer re-arm here.
    });

    return Scaffold(
      body: widget.navigationShell,
      // Theme only the nav bar (not the screen bodies) so it's Aurora-dark
      // across the app while individual screens migrate.
      bottomNavigationBar: Theme(
        data: AppTheme.aurora.copyWith(
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Aurora.bgTop,
            indicatorColor: Aurora.accentGreen.withValues(alpha: 0.18),
            surfaceTintColor: Colors.transparent,
            iconTheme: WidgetStateProperty.resolveWith(
              (s) => IconThemeData(
                color: s.contains(WidgetState.selected)
                    ? Aurora.accentGreen
                    : Aurora.textMuted,
              ),
            ),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (s) => TextStyle(
                fontSize: 12,
                fontFamily: 'Plus Jakarta Sans',
                fontWeight: FontWeight.w600,
                color: s.contains(WidgetState.selected)
                    ? Aurora.accentGreen
                    : Aurora.textMuted,
              ),
            ),
          ),
        ),
        child: NavigationBar(
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
      ),
    );
  }
}
