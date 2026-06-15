import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/experiment.dart';
import 'package:hearty_app/features/experiments/widgets/experiment_nudge_dialog.dart';

/// Records which lifecycle action the nudge dialog invoked, with the id passed.
class _FakeApi implements HeartyApiClient {
  final List<String> ackCalls = [];
  final List<String> restartCalls = [];
  final List<String> abandonCalls = [];

  /// When true, abandonExperiment throws (simulates a failed action) so the
  /// pop-only-on-success path can be asserted.
  bool failAbandon = false;

  @override
  Future<void> ackExperimentNudge(String id) async => ackCalls.add(id);

  @override
  Future<Experiment> restartExperiment(String id) async {
    restartCalls.add(id);
    return Experiment(
      id: id,
      category: 'dairy',
      direction: 'eliminate',
      outcomeType: 'symptom',
      outcomeName: 'bloating',
      experimentStart: '2026-06-15',
      experimentEnd: '2026-06-29',
      status: 'running',
    );
  }

  @override
  Future<void> abandonExperiment(String id) async {
    abandonCalls.add(id);
    if (failAbandon) throw Exception('abandon failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Experiment _exp() => const Experiment(
      id: 'exp-7',
      category: 'dairy',
      direction: 'eliminate',
      outcomeType: 'symptom',
      outcomeName: 'bloating',
      experimentStart: '2026-06-01',
      experimentEnd: '2026-06-15',
      status: 'running',
      nudgeSuggested: true,
    );

Future<_FakeApi> _pump(WidgetTester tester) async {
  final api = _FakeApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [heartyApiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Scaffold(
          body: ExperimentNudgeDialog(experiment: _exp()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('Keep going → ackExperimentNudge(id) then dismisses',
      (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.byKey(const Key('experiment-nudge-keep')));
    await tester.pumpAndSettle();

    expect(api.ackCalls, ['exp-7']);
    expect(api.restartCalls, isEmpty);
    expect(api.abandonCalls, isEmpty);
    expect(find.byKey(const Key('experiment-nudge-dialog')), findsNothing);
  });

  testWidgets('Restart the clock → restartExperiment(id) then dismisses',
      (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.byKey(const Key('experiment-nudge-restart')));
    await tester.pumpAndSettle();

    expect(api.restartCalls, ['exp-7']);
    expect(api.ackCalls, isEmpty);
    expect(api.abandonCalls, isEmpty);
    expect(find.byKey(const Key('experiment-nudge-dialog')), findsNothing);
  });

  testWidgets('Stop → abandonExperiment(id) then dismisses', (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.byKey(const Key('experiment-nudge-stop')));
    await tester.pumpAndSettle();

    expect(api.abandonCalls, ['exp-7']);
    expect(api.ackCalls, isEmpty);
    expect(api.restartCalls, isEmpty);
    expect(find.byKey(const Key('experiment-nudge-dialog')), findsNothing);
  });

  testWidgets('a failed action does NOT dismiss the dialog', (tester) async {
    final api = await _pump(tester);
    api.failAbandon = true;

    await tester.tap(find.byKey(const Key('experiment-nudge-stop')));
    await tester.pumpAndSettle();

    // The client call still happened, but the thrown error must leave the
    // dialog open rather than pop it as if the action succeeded.
    expect(api.abandonCalls, ['exp-7']);
    expect(find.byKey(const Key('experiment-nudge-dialog')), findsOneWidget);
  });
}
