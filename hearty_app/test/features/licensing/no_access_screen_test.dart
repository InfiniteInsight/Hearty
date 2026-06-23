import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/licensing/no_access_screen.dart';

void main() {
  group('NoAccessScreen', () {
    testWidgets('shows the no-access message and a Sign out action',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NoAccessScreen()),
        ),
      );

      expect(find.textContaining('No active access'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign out'), findsOneWidget);
    });

    testWidgets('is non-dismissable (PopScope blocks back)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: NoAccessScreen()),
        ),
      );

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });
}
