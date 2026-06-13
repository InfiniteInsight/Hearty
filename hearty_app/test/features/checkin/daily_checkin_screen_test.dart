import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/checkin_gap.dart';
import 'package:hearty_app/features/checkin/screens/daily_checkin_screen.dart';

/// Records every call to the five check-in methods and returns a canned
/// [CheckinGapsResult]. Mirrors the fake in `checkin_controller_test.dart` so
/// the widget tests drive REAL controller transitions through an overridden
/// [heartyApiClientProvider] (the family StateNotifier is left untouched).
class FakeHeartyApiClient implements HeartyApiClient {
  FakeHeartyApiClient({
    CheckinGapsResult? gapsResult,
    this.throwOnFetch = false,
  }) : _gapsResult = gapsResult;

  CheckinGapsResult? _gapsResult;
  bool throwOnFetch;

  final List<DateTime> fetchedDates = [];
  final List<Map<String, dynamic>> resolveSymptomCalls = [];
  final List<String> skipSymptomMealIds = [];
  final List<Map<String, dynamic>> resolveFoodCalls = [];
  final List<Map<String, dynamic>> resolveMealCalls = [];

  @override
  Future<CheckinGapsResult> fetchCheckinGaps(DateTime date) async {
    fetchedDates.add(date);
    if (throwOnFetch) throw Exception('boom');
    return _gapsResult!;
  }

  @override
  Future<void> resolveSymptomGap({
    required String mealId,
    required String rawDescription,
    String? symptomType,
    int? severity,
    int? onsetMinutes,
    DateTime? loggedAt,
  }) async {
    resolveSymptomCalls.add({
      'mealId': mealId,
      'rawDescription': rawDescription,
      'severity': severity,
      'loggedAt': loggedAt,
    });
  }

  @override
  Future<void> skipSymptomGap({required String mealId}) async {
    skipSymptomMealIds.add(mealId);
  }

  @override
  Future<void> resolveFoodGap({
    required String mealId,
    String? foodName,
    bool? confirmed,
    String? correctedDescription,
  }) async {
    resolveFoodCalls.add({
      'mealId': mealId,
      'foodName': foodName,
      'confirmed': confirmed,
      'correctedDescription': correctedDescription,
    });
  }

  @override
  Future<void> resolveMealGap({
    required String description,
    required DateTime loggedAt,
  }) async {
    resolveMealCalls.add({'description': description, 'loggedAt': loggedAt});
  }

  // Any other client method being hit is a test failure, not a silent no-op.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CheckinGap _symptom(String mealId) =>
    CheckinGap(type: 'symptom_gap', prompt: 'How did your stomach feel?', mealId: mealId);

CheckinGap _lowConfidence(String mealId, String foodName) => CheckinGap(
      type: 'low_confidence',
      prompt: 'Was it $foodName?',
      mealId: mealId,
      foodName: foodName,
    );

const _date = '2026-06-13';

CheckinGapsResult _result({
  required List<CheckinGap> gaps,
  bool expired = false,
}) =>
    CheckinGapsResult(targetDate: _date, expired: expired, gaps: gaps);

Future<FakeHeartyApiClient> _pump(
  WidgetTester tester, {
  required CheckinGapsResult? result,
  bool throwOnFetch = false,
}) async {
  final api = FakeHeartyApiClient(gapsResult: result, throwOnFetch: throwOnFetch);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        heartyApiClientProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(home: DailyCheckinScreen(date: _date)),
    ),
  );
  // First frame paints the loading spinner; settle the post-frame load().
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('preview → begin → answer first symptom gap → resolve called',
      (tester) async {
    final api = await _pump(
      tester,
      result: _result(gaps: [_symptom('m1'), _lowConfidence('m2', 'rice')]),
    );

    // Preview shows both gaps.
    expect(find.text('2 things to review'), findsOneWidget);
    expect(find.byKey(const Key('checkin-begin')), findsOneWidget);

    await tester.tap(find.byKey(const Key('checkin-begin')));
    await tester.pumpAndSettle();

    // First (symptom) gap is up.
    expect(find.text('How did your stomach feel?'), findsOneWidget);
    expect(find.byKey(const Key('checkin-progress')), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('checkin-symptom-answer')),
      'bloated',
    );
    await tester.enterText(
      find.byKey(const Key('checkin-symptom-severity')),
      '4',
    );
    await tester.tap(find.byKey(const Key('checkin-submit')));
    await tester.pumpAndSettle();

    // resolveSymptom was dispatched with the entered values.
    expect(api.resolveSymptomCalls, hasLength(1));
    expect(api.resolveSymptomCalls.single['mealId'], 'm1');
    expect(api.resolveSymptomCalls.single['rawDescription'], 'bloated');
    expect(api.resolveSymptomCalls.single['severity'], 4);

    // Cycle advanced to the second gap (and stale symptom text did not bleed).
    expect(find.text('Was it rice?'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.byKey(const Key('checkin-symptom-answer')), findsNothing);
  });

  testWidgets('skip-all → begin → done, no resolve/skip-server calls',
      (tester) async {
    final api = await _pump(
      tester,
      result: _result(gaps: [_symptom('m1'), _lowConfidence('m2', 'rice')]),
    );

    await tester.tap(find.byKey(const Key('checkin-skip-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkin-begin')));
    await tester.pumpAndSettle();

    // Non-empty, non-expired done → the "everything" card.
    expect(find.byKey(const Key('checkin-done')), findsOneWidget);
    expect(find.text("That's everything for today 🎉"), findsOneWidget);

    // Preview-skip is in-memory only — no server calls for the skipped gaps.
    expect(api.resolveSymptomCalls, isEmpty);
    expect(api.skipSymptomMealIds, isEmpty);
    expect(api.resolveFoodCalls, isEmpty);
    expect(api.resolveMealCalls, isEmpty);
  });

  testWidgets('expired result → expired end card', (tester) async {
    await _pump(
      tester,
      result: _result(gaps: [_symptom('m1')], expired: true),
    );

    expect(find.byKey(const Key('checkin-done')), findsOneWidget);
    expect(find.text('This review has expired.'), findsOneWidget);
  });

  testWidgets('empty (non-expired) → caught-up end card', (tester) async {
    await _pump(tester, result: _result(gaps: []));

    expect(find.byKey(const Key('checkin-done')), findsOneWidget);
    expect(find.text("Nothing to review — you're all caught up."),
        findsOneWidget);
  });

  testWidgets('fetch throws → error card, retry re-runs load', (tester) async {
    final api = await _pump(tester, result: null, throwOnFetch: true);

    expect(find.byKey(const Key('checkin-error')), findsOneWidget);
    expect(find.text("Couldn't load your check-in."), findsOneWidget);
    expect(api.fetchedDates, hasLength(1));

    // Let retry succeed this time.
    api.throwOnFetch = false;
    api._gapsResult = _result(gaps: [_symptom('m1')]);
    await tester.tap(find.byKey(const Key('checkin-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkin-error')), findsNothing);
    expect(find.text('1 thing to review'), findsOneWidget);
    expect(api.fetchedDates, hasLength(2));
  });
}
