import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/onboarding_provider.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/logging/screens/home_screen.dart';
import '../features/history/screens/history_screen.dart';
import '../features/trends/screens/trends_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/logging/screens/log_entry_screen.dart';
import '../features/health_profile/screens/health_profile_screen.dart';
import '../features/logging/screens/log_detail_screen.dart';
import '../features/logging/screens/onboarding_screen.dart';

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
    initialLocation: '/home',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuthenticated = session != null;
      final location = state.matchedLocation;
      final isOnSignIn = location == '/sign-in';
      final isOnOnboarding = location == '/onboarding';
      final hasCompletedOnboarding =
          ref.read(hasCompletedOnboardingProvider).valueOrNull ?? false;

      if (!isAuthenticated && !isOnSignIn) return '/sign-in';
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

class _ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _ScaffoldWithNavBar({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
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
