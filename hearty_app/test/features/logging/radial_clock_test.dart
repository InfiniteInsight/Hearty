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

  // Sample day from the arc-labels companion spec: AM entries (outer ring)
  // and PM entries (inner ring).
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
                selectedIds: const {'lunch'},
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
    Set<String>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RadialClock(
              time: DateTime(2026, 6, 28, 14, 34),
              entries: sampleEntries,
              onSelect: (ids) => selected = ids,
            ),
          ),
        ),
      ),
    );
    // Lunch is 12:30 PM → inner ring (R=60) at ~15°. Offset ≈ (+16, -58).
    final center = tester.getCenter(find.byType(RadialClock));
    await tester.tapAt(center + const Offset(16, -58));
    await tester.pump();
    expect(selected, {'lunch'});
  });

  // Co-timed meal + symptom merge into one split bubble.
  final coTimed = [
    ClockEntry(id: 'liquidiv', label: 'Liquid IV', time: DateTime(2026, 6, 28, 13, 4), type: ClockEntryType.meal),
    ClockEntry(id: 'reflux', label: 'acid reflux', time: DateTime(2026, 6, 28, 13, 4), type: ClockEntryType.symptom),
  ];

  testWidgets('co-timed entries render a split bubble golden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: Aurora.background),
            child: Center(
              child: RadialClock(
                time: DateTime(2026, 6, 28, 14, 34),
                entries: coTimed,
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RadialClock),
      matchesGoldenFile('goldens/radial_clock_split.png'),
    );
  });

  testWidgets('tapping a split bubble selects all its entries', (tester) async {
    Set<String>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RadialClock(
              time: DateTime(2026, 6, 28, 14, 34),
              entries: coTimed,
              onSelect: (ids) => selected = ids,
            ),
          ),
        ),
      ),
    );
    // Bubble center for 1:04 PM (angle ≈ 32°) → inner ring (R=60): offset ≈ (+32, -51).
    final center = tester.getCenter(find.byType(RadialClock));
    // Tap anywhere on the merged bubble → both entries selected.
    await tester.tapAt(center + const Offset(32, -51));
    await tester.pump();
    expect(selected, {'liquidiv', 'reflux'});
  });

  testWidgets('split bubble popup stacks both entries', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RadialClock(
              time: DateTime(2026, 6, 28, 14, 34),
              entries: coTimed,
              selectedIds: const {'liquidiv', 'reflux'},
            ),
          ),
        ),
      ),
    );
    // Both entry labels appear in the stacked popup.
    expect(find.text('Liquid IV'), findsOneWidget);
    expect(find.text('acid reflux'), findsOneWidget);
  });
}
