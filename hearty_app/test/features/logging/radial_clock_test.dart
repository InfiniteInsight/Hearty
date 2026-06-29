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

  testWidgets('RadialClock with orbit entries golden', (tester) async {
    // Sample day from the arc-labels companion spec: AM entries (inner ring)
    // and PM entries (outer ring).
    final entries = [
      ClockEntry(time: DateTime(2026, 6, 28, 8, 0), type: ClockEntryType.meal),
      ClockEntry(time: DateTime(2026, 6, 28, 9, 0), type: ClockEntryType.meal),
      ClockEntry(
        time: DateTime(2026, 6, 28, 10, 30),
        type: ClockEntryType.symptom,
      ),
      ClockEntry(time: DateTime(2026, 6, 28, 12, 30), type: ClockEntryType.meal),
      ClockEntry(time: DateTime(2026, 6, 28, 14, 0), type: ClockEntryType.meal),
      ClockEntry(time: DateTime(2026, 6, 28, 16, 0), type: ClockEntryType.mood),
      ClockEntry(time: DateTime(2026, 6, 28, 19, 0), type: ClockEntryType.meal),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: Aurora.background),
            child: Center(
              child: RadialClock(
                time: DateTime(2026, 6, 28, 14, 34),
                entries: entries,
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
}
