import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/checkin_gap.dart';
import 'package:hearty_app/core/api/models/user_preferences.dart';
import 'package:hearty_app/core/api/providers/preferences_provider.dart';
import 'package:hearty_app/features/checkin/widgets/home_checkin_banner.dart';

/// Minimal fake — only [fetchCheckinGaps] is exercised by the banner.
class _FakeApi implements HeartyApiClient {
  _FakeApi({this.result, this.throwOnFetch = false});

  CheckinGapsResult? result;
  bool throwOnFetch;
  final List<DateTime> fetchedDates = [];

  @override
  Future<CheckinGapsResult> fetchCheckinGaps(DateTime date) async {
    fetchedDates.add(date);
    if (throwOnFetch) throw Exception('boom');
    return result!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CheckinGap _gap(String mealId) =>
    CheckinGap(type: 'symptom_gap', prompt: 'How did it feel?', mealId: mealId);

CheckinGapsResult _result({required List<CheckinGap> gaps, bool expired = false}) =>
    CheckinGapsResult(targetDate: '2026-06-13', expired: expired, gaps: gaps);

/// Pumps [HomeCheckinBanner] inside a GoRouter (so `context.push('/checkin')`
/// resolves) with the api + prefs providers overridden.
Future<_FakeApi> _pumpBanner(
  WidgetTester tester, {
  required CheckinGapsResult? result,
  bool throwOnFetch = false,
  bool checkinEnabled = true,
}) async {
  final api = _FakeApi(result: result, throwOnFetch: throwOnFetch);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: HomeCheckinBanner()),
      ),
      GoRoute(
        path: '/checkin',
        builder: (context, state) =>
            const Scaffold(body: Text('CHECKIN SCREEN', key: Key('stub-checkin'))),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        heartyApiClientProvider.overrideWithValue(api),
        preferencesProvider.overrideWith(
          () => _StubPrefs(UserPreferences(dailyCheckinEnabled: checkinEnabled)),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

/// AsyncNotifier stub that resolves immediately to a fixed [UserPreferences].
class _StubPrefs extends PreferencesNotifier {
  _StubPrefs(this._prefs);
  final UserPreferences _prefs;
  @override
  Future<UserPreferences> build() async => _prefs;
}

void main() {
  group('HomeCheckinBanner (provider-gated)', () {
    testWidgets('gaps present + enabled → banner shows count', (tester) async {
      await _pumpBanner(tester, result: _result(gaps: [_gap('m1'), _gap('m2')]));

      expect(find.byKey(const Key('home-checkin-banner')), findsOneWidget);
      expect(find.text('Review my day — 2 things to check'), findsOneWidget);
    });

    testWidgets('singular count copy', (tester) async {
      await _pumpBanner(tester, result: _result(gaps: [_gap('m1')]));
      expect(find.text('Review my day — 1 thing to check'), findsOneWidget);
    });

    testWidgets('tapping banner navigates to /checkin', (tester) async {
      await _pumpBanner(tester, result: _result(gaps: [_gap('m1')]));

      await tester.tap(find.byKey(const Key('home-checkin-banner')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-checkin')), findsOneWidget);
    });

    testWidgets('empty gaps → no banner', (tester) async {
      await _pumpBanner(tester, result: _result(gaps: []));
      expect(find.byKey(const Key('home-checkin-banner')), findsNothing);
    });

    testWidgets('expired result → no banner', (tester) async {
      await _pumpBanner(tester, result: _result(gaps: [_gap('m1')], expired: true));
      expect(find.byKey(const Key('home-checkin-banner')), findsNothing);
    });

    testWidgets('checkin disabled in prefs → no banner even with gaps',
        (tester) async {
      await _pumpBanner(
        tester,
        result: _result(gaps: [_gap('m1')]),
        checkinEnabled: false,
      );
      expect(find.byKey(const Key('home-checkin-banner')), findsNothing);
    });

    testWidgets('fetch error → no banner (silent)', (tester) async {
      await _pumpBanner(tester, result: null, throwOnFetch: true);
      expect(find.byKey(const Key('home-checkin-banner')), findsNothing);
    });
  });

  group('CheckinBannerView (pure presentation)', () {
    testWidgets('renders count and fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckinBannerView(count: 3, onTap: () => tapped = true),
          ),
        ),
      );
      expect(find.text('Review my day — 3 things to check'), findsOneWidget);

      await tester.tap(find.byType(CheckinBannerView));
      expect(tapped, isTrue);
    });
  });
}
