import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/symptom_log.dart';
import 'package:hearty_app/core/api/providers/symptoms_provider.dart';
import 'package:hearty_app/features/logging/widgets/feeling_followup_sheet.dart';

/// Records every [logSymptom] call with its raw arguments. Overriding at the
/// notifier level (not the DAO) is required: the real notifier coerces
/// `severity ?? 1` before the DAO sees it, so a DAO fake could never observe the
/// "severity null" case. The fake also stubs [build] so it never touches the
/// DAO or sync trigger.
class FakeSymptomsNotifier extends SymptomsNotifier {
  final List<({String description, int? severity})> calls = [];

  @override
  Stream<List<SymptomLog>> build() => Stream.value(const []);

  @override
  Future<void> logSymptom(String description, {int? severity}) async {
    calls.add((description: description, severity: severity));
  }
}

/// Stubs the sentiment classifier. [result] is what `classifyFeeling` returns;
/// [throws] simulates an offline/error path.
class FakeApiClient extends HeartyApiClient {
  FakeApiClient({this.result = true, this.throws = false}) : super(Dio());
  final bool result;
  final bool throws;
  int classifyCalls = 0;

  @override
  Future<bool> classifyFeeling(String text) async {
    classifyCalls++;
    if (throws) throw Exception('offline');
    return result;
  }
}

Future<(FakeSymptomsNotifier, FakeApiClient)> _pump(
  WidgetTester tester, {
  bool classify = true,
  bool classifyThrows = false,
}) async {
  final fake = FakeSymptomsNotifier();
  final api = FakeApiClient(result: classify, throws: classifyThrows);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        symptomsProvider.overrideWith(() => fake),
        heartyApiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showFeelingFollowUp(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (fake, api);
}

void main() {
  testWidgets('negative note + Save → classified, logSymptom called once',
      (tester) async {
    final (fake, api) = await _pump(tester, classify: true);

    await tester.enterText(
      find.byKey(const Key('feeling-note-field')),
      'felt bloated',
    );
    await tester.tap(find.byKey(const Key('feeling-save')));
    await tester.pumpAndSettle();

    expect(api.classifyCalls, 1);
    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.description, 'felt bloated');
    expect(fake.calls.single.severity, isNull);
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });

  testWidgets('positive note + Save → classified false → NOT logged, closes',
      (tester) async {
    final (fake, api) = await _pump(tester, classify: false);

    await tester.enterText(
      find.byKey(const Key('feeling-note-field')),
      'feeling good',
    );
    await tester.tap(find.byKey(const Key('feeling-save')));
    await tester.pumpAndSettle();

    expect(api.classifyCalls, 1);
    expect(fake.calls, isEmpty);
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });

  testWidgets('classify error → NOT logged (conservative), closes',
      (tester) async {
    final (fake, api) = await _pump(tester, classifyThrows: true);

    await tester.enterText(
      find.byKey(const Key('feeling-note-field')),
      'felt bloated',
    );
    await tester.tap(find.byKey(const Key('feeling-save')));
    await tester.pumpAndSettle();

    expect(api.classifyCalls, 1);
    expect(fake.calls, isEmpty);
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });

  testWidgets('severity + Save → logged WITHOUT classifying', (tester) async {
    final (fake, api) = await _pump(tester);

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feeling-save')));
    await tester.pumpAndSettle();

    expect(api.classifyCalls, 0); // rating is an explicit discomfort signal
    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.severity, 5);
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });

  testWidgets('Skip → nothing logged, no classify, sheet closes',
      (tester) async {
    final (fake, api) = await _pump(tester);

    await tester.tap(find.byKey(const Key('feeling-skip')));
    await tester.pumpAndSettle();

    expect(api.classifyCalls, 0);
    expect(fake.calls, isEmpty);
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });

  testWidgets('empty note + no severity + Save → nothing, no classify',
      (tester) async {
    final (fake, api) = await _pump(tester);

    await tester.tap(find.byKey(const Key('feeling-save')));
    await tester.pumpAndSettle();

    expect(api.classifyCalls, 0);
    expect(fake.calls, isEmpty);
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });
}
