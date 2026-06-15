import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/experiment.dart';
import 'package:hearty_app/core/api/models/trends_turn.dart';
import 'package:hearty_app/features/trends/screens/trends_conversation_screen.dart';

/// Records the two trends methods and returns a scripted [TrendsTurn], so the
/// widget test drives REAL controller transitions through an overridden
/// [heartyApiClientProvider] (the autoDispose StateNotifier is left untouched).
class FakeHeartyApiClient implements HeartyApiClient {
  FakeHeartyApiClient(this._turn);

  final TrendsTurn _turn;

  final List<Map<String, dynamic>> verdictCalls = [];
  final List<Map<String, dynamic>> experimentCalls = [];

  @override
  Future<TrendsTurn> trendsConversation(List<Map<String, String>> history) async {
    return _turn;
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
  Future<Experiment> createExperiment({
    required String category,
    required String outcomeType,
    required String outcomeName,
  }) async {
    experimentCalls.add({
      'category': category,
      'outcomeType': outcomeType,
      'outcomeName': outcomeName,
    });
    return Experiment(
      id: 'exp-1',
      category: category,
      direction: 'eliminate',
      outcomeType: outcomeType,
      outcomeName: outcomeName,
      experimentStart: '2026-06-15',
      experimentEnd: '2026-06-29',
      status: 'running',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _router() => GoRouter(
      initialLocation: '/trends-conversation',
      routes: [
        GoRoute(
          path: '/trends-conversation',
          builder: (context, state) => const TrendsConversationScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) =>
              const Scaffold(body: Text('home-stub')),
        ),
      ],
    );

Future<FakeHeartyApiClient> _pump(WidgetTester tester, TrendsTurn turn) async {
  final api = FakeHeartyApiClient(turn);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [heartyApiClientProvider.overrideWithValue(api)],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('proposed verdict → Confirm submits once with the right args',
      (tester) async {
    final api = await _pump(
      tester,
      const TrendsTurn(
        reply: 'I noticed something about dairy.',
        proposedVerdict: ProposedVerdict(
          category: 'dairy',
          outcomeType: 'symptom',
          outcomeName: 'bloating',
          verdict: 'confirmed',
        ),
      ),
    );

    // Active conversation with the verdict chip.
    expect(find.text('I noticed something about dairy.'), findsOneWidget);
    expect(find.byKey(const Key('trends-verdict-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const Key('trends-verdict-confirm')));
    await tester.pumpAndSettle();

    expect(api.verdictCalls, hasLength(1));
    expect(api.verdictCalls.single, {
      'category': 'dairy',
      'outcomeType': 'symptom',
      'outcomeName': 'bloating',
      'verdict': 'confirmed',
    });
    // Chip is gone once resolved.
    expect(find.byKey(const Key('trends-verdict-confirm')), findsNothing);
  });

  testWidgets('Not now dismisses the verdict without an API call',
      (tester) async {
    final api = await _pump(
      tester,
      const TrendsTurn(
        reply: 'I noticed something about dairy.',
        proposedVerdict: ProposedVerdict(
          category: 'dairy',
          outcomeType: 'symptom',
          outcomeName: 'bloating',
          verdict: 'confirmed',
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('trends-verdict-dismiss')));
    await tester.pumpAndSettle();

    expect(api.verdictCalls, isEmpty);
    expect(find.byKey(const Key('trends-verdict-confirm')), findsNothing);
  });

  testWidgets(
      'proposed experiment → Start creates it once with the right args',
      (tester) async {
    final api = await _pump(
      tester,
      const TrendsTurn(
        reply: 'Want to test cutting dairy?',
        proposedExperiment: ProposedExperiment(
          category: 'dairy',
          outcomeType: 'symptom',
          outcomeName: 'bloating',
        ),
      ),
    );

    // Active conversation with the experiment chip.
    expect(find.text('Want to test cutting dairy?'), findsOneWidget);
    expect(find.byKey(const Key('trends-experiment-chip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('trends-experiment-chip')));
    await tester.pumpAndSettle();

    expect(api.experimentCalls, hasLength(1));
    expect(api.experimentCalls.single, {
      'category': 'dairy',
      'outcomeType': 'symptom',
      'outcomeName': 'bloating',
    });
    // Chip is gone once the experiment is created.
    expect(find.byKey(const Key('trends-experiment-chip')), findsNothing);
  });

  testWidgets('isClosing turn shows Done → close moves to the end card',
      (tester) async {
    await _pump(
      tester,
      const TrendsTurn(reply: 'All caught up for this month.', isClosing: true),
    );

    expect(find.byKey(const Key('trends-caught-up')), findsOneWidget);
    await tester.tap(find.byKey(const Key('trends-done')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trends-closed')), findsOneWidget);
  });
}
