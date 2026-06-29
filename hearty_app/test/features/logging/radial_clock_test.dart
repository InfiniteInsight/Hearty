import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/app/theme/aurora_colors.dart';
import 'package:hearty_app/features/logging/widgets/radial_clock.dart';

void main() {
  testWidgets('RadialClock builds without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: RadialClock(time: DateTime(2026, 6, 28, 14, 34))),
        ),
      ),
    );
    expect(find.byType(RadialClock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RadialClock Aurora golden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: Aurora.background),
            child: Center(
              child: RadialClock(time: DateTime(2026, 6, 28, 14, 34)),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RadialClock),
      matchesGoldenFile('goldens/radial_clock_aurora.png'),
    );
  });

  // Sample day from the arc-labels companion spec: AM entries (inner ring)
  // and PM entries (outer ring).
  final sampleEntries = [
    ClockEntry(id: 'breakfast', label: 'Breakfast', time: DateTime(2026, 6, 28, 8, 0), type: ClockEntryType.meal),
    ClockEntry(id: 'coffee', label: 'Coffee', time: DateTime(2026, 6, 28, 9, 0), type: ClockEntryType.meal),
    ClockEntry(id: 'bloating', label: 'Bloating', time: DateTime(2026, 6, 28, 10, 30), type: ClockEntryType.symptom),
    ClockEntry(id: 'lunch', label: 'Caesar Salad', time: DateTime(2026, 6, 28, 12, 30), type: ClockEntryType.meal),
    ClockEntry(id: 'snack', label: 'Snack', time: DateTime(2026, 6, 28, 14, 0), type: ClockEntryType.meal),
    ClockEntry(id: 'mood', label: 'Mood', time: DateTime(2026, 6, 28, 16, 0), type: ClockEntryType.mood),
    ClockEntry(id: 'dinner', label: 'Dinner', time: DateTime(2026, 6, 28, 19, 0), type: ClockEntryType.meal),
  ];

  testWidgets('RadialClock with orbit entries golden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: Aurora.background),
            child: Center(
              child: RadialClock(
                time: DateTime(2026, 6, 28, 14, 34),
                entries: sampleEntries,
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RadialClock),
      matchesGoldenFile('goldens/radial_clock_entries.png'),
    );
  });

  testWidgets('RadialClock selected dot + popup golden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: Aurora.background),
            child: Center(
              child: RadialClock(
                time: DateTime(2026, 6, 28, 14, 34),
                entries: sampleEntries,
                selectedId: 'lunch',
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RadialClock),
      matchesGoldenFile('goldens/radial_clock_selected.png'),
    );
  });

  testWidgets('tapping a dot reports selection', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RadialClock(
              time: DateTime(2026, 6, 28, 14, 34),
              entries: sampleEntries,
              onSelect: (id) => selected = id,
            ),
          ),
        ),
      ),
    );
    // Tap the Lunch dot — offset (+31, -114) from clock center per the spec.
    final center = tester.getCenter(find.byType(RadialClock));
    await tester.tapAt(center + const Offset(31, -114));
    await tester.pump();
    expect(selected, 'lunch');
  });
}
