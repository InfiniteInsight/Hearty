import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/experiment.dart';
import 'package:hearty_app/features/experiments/screens/experiment_result_screen.dart';

/// Fake api client recording the calls the result screen makes:
/// [evaluateExperiment] (always, on open) and [submitSignalVerdict] (only when
/// the user taps the confirm chip on an `improved` result).
class _FakeApi implements HeartyApiClient {
  _FakeApi(this._result);

  final Map<String, dynamic>? _result;
  final List<String> evaluatedIds = [];
  final List<Map<String, dynamic>> verdictCalls = [];

  @override
  Future<Experiment> evaluateExperiment(String id) async {
    evaluatedIds.add(id);
    return Experiment(
      id: id,
      category: 'dairy_casein',
      categoryLabel: 'Dairy / Casein',
      direction: 'eliminate',
      outcomeType: 'symptom',
      outcomeName: 'bloating',
      experimentStart: '2026-06-01',
      experimentEnd: '2026-06-15',
      status: 'completed',
      result: _result,
    );
  }

  @override
  Future<void> submitSignalVerdict({
    required String category,
    required String outcomeType,
    required String outcomeName,
    required String verdict,
  }) async {
    verdictCalls.add({
      'category': category,
      'outcomeType': outcomeType,
      'outcomeName': outcomeName,
      'verdict': verdict,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeApi> _pump(
  WidgetTester tester,
  Map<String, dynamic>? result,
) async {
  final api = _FakeApi(result);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [heartyApiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(
        home: ExperimentResultScreen(experimentId: 'exp-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('improved → confirm chip present; tap submits confirmed once',
      (tester) async {
    final api = await _pump(tester, {
      'verdict': 'improved',
      'reason': null,
      'adherence': 0.9,
      'logged_days': 14,
    });

    expect(api.evaluatedIds, ['exp-1']);
    expect(
      find.text(
          'Cutting Dairy / Casein seems to have helped — bloating improved.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('experiment-confirm-chip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('experiment-confirm-chip')));
    await tester.pumpAndSettle();

    expect(api.verdictCalls, hasLength(1));
    // Write-back uses the raw slug, not the friendly label.
    expect(api.verdictCalls.single, {
      'category': 'dairy_casein',
      'outcomeType': 'symptom',
      'outcomeName': 'bloating',
      'verdict': 'confirmed',
    });
    // Chip disappears once confirmed.
    expect(find.byKey(const Key('experiment-confirm-chip')), findsNothing);
    expect(find.byKey(const Key('experiment-confirm-done')), findsOneWidget);
  });

  testWidgets('no_change → neutral copy, no confirm chip', (tester) async {
    final api = await _pump(tester, {'verdict': 'no_change', 'reason': null});

    expect(find.text('No clear change from cutting Dairy / Casein.'),
        findsOneWidget);
    expect(find.byKey(const Key('experiment-confirm-chip')), findsNothing);
    expect(api.verdictCalls, isEmpty);
  });

  testWidgets('worse → no confirm chip', (tester) async {
    await _pump(tester, {'verdict': 'worse', 'reason': null});

    expect(find.byKey(const Key('experiment-confirm-chip')), findsNothing);
  });

  testWidgets('inconclusive/low_adherence → adherence copy, no chip',
      (tester) async {
    final api = await _pump(tester, {
      'verdict': 'inconclusive',
      'reason': 'low_adherence',
    });

    expect(
      find.text(
          'Not enough clean days to tell — Dairy / Casein showed up too often '
          'during the test.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('experiment-confirm-chip')), findsNothing);
    expect(api.verdictCalls, isEmpty);
  });

  testWidgets('inconclusive/thin_data → thin-data copy, no chip',
      (tester) async {
    await _pump(tester, {'verdict': 'inconclusive', 'reason': 'thin_data'});

    expect(
      find.text('Not enough logged data to draw a conclusion.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('experiment-confirm-chip')), findsNothing);
  });
}
