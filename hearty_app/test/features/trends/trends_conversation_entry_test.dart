import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearty_app/core/api/models/user_preferences.dart';
import 'package:hearty_app/core/api/providers/preferences_provider.dart';
import 'package:hearty_app/features/trends/widgets/trends_conversation_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// AsyncNotifier stub that resolves immediately to a fixed [UserPreferences].
class _StubPrefs extends PreferencesNotifier {
  _StubPrefs(this._prefs);
  final UserPreferences _prefs;
  @override
  Future<UserPreferences> build() async => _prefs;
}

/// Pumps [TrendsConversationEntry] inside a GoRouter (so
/// `context.push('/trends-conversation')` resolves) with the prefs provider
/// overridden.
Future<void> _pumpEntry(
  WidgetTester tester, {
  required bool enabled,
}) async {
  final router = GoRouter(
    initialLocation: '/trends',
    routes: [
      GoRoute(
        path: '/trends',
        builder: (context, state) =>
            const Scaffold(body: TrendsConversationEntry()),
      ),
      GoRoute(
        path: '/trends-conversation',
        builder: (context, state) => const Scaffold(
          body: Text('TRENDS CONVO', key: Key('stub-trends-convo')),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWith(
          () => _StubPrefs(UserPreferences(trendsConversationEnabled: enabled)),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('TrendsConversationEntry (provider-gated)', () {
    testWidgets('enabled → entry shows', (tester) async {
      await _pumpEntry(tester, enabled: true);
      expect(find.byKey(const Key('trends-convo-entry')), findsOneWidget);
      expect(find.text('Talk about my trends'), findsOneWidget);
    });

    testWidgets('disabled → renders nothing', (tester) async {
      await _pumpEntry(tester, enabled: false);
      expect(find.byKey(const Key('trends-convo-entry')), findsNothing);
    });

    testWidgets('tapping routes to /trends-conversation', (tester) async {
      await _pumpEntry(tester, enabled: true);

      await tester.tap(find.byKey(const Key('trends-convo-entry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-trends-convo')), findsOneWidget);
    });
  });
}
