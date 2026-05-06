import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
}

final goRouter = GoRouter(
  initialLocation: '/home',
  // TODO Phase 3: redirect unauthenticated users to /sign-in
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
