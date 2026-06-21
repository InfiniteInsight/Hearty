import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Pumps a button that opens the sheet via [showFeelingFollowUp]. Driving it
/// through a real route lets the Skip / empty-Save cases pop a real route, so we
/// can assert the sheet actually closes.
Future<FakeSymptomsNotifier> _pump(WidgetTester tester) async {
  final fake = FakeSymptomsNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        symptomsProvider.overrideWith(() => fake),
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
  return fake;
}

void main() {
  testWidgets('note + Save → logSymptom called once with note, severity null',
      (tester) async {
    final fake = await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('feeling-note-field')),
      'felt bloated',
    );
    await tester.tap(find.byKey(const Key('feeling-save')));
    await tester.pumpAndSettle();

    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.description, 'felt bloated');
    expect(fake.calls.single.severity, isNull);
    // Sheet closed.
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });

  testWidgets('severity + Save → logSymptom called with that severity',
      (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feeling-save')));
    await tester.pumpAndSettle();

    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.severity, 5);
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });

  testWidgets('Skip → logSymptom NOT called, sheet closes', (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.byKey(const Key('feeling-skip')));
    await tester.pumpAndSettle();

    expect(fake.calls, isEmpty);
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });

  testWidgets('empty note + no severity + Save → NOT called, sheet closes',
      (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.byKey(const Key('feeling-save')));
    await tester.pumpAndSettle();

    expect(fake.calls, isEmpty);
    expect(find.byKey(const Key('feeling-note-field')), findsNothing);
  });
}
