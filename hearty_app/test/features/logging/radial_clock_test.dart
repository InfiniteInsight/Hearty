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
}
