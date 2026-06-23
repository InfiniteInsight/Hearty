import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/licensing/license_provider.dart';
import 'package:hearty_app/features/licensing/no_access_screen.dart';

ProviderScope _scope(Widget child, {String status = 'none'}) => ProviderScope(
      // Override so the screen doesn't hit the real status fetch / Supabase.
      overrides: [licenseStatusProvider.overrideWith((ref) async => status)],
      child: MaterialApp(home: child),
    );

void main() {
  group('NoAccessScreen', () {
    testWidgets('shows the no-access message, Check again, and Sign out',
        (tester) async {
      await tester.pumpWidget(_scope(const NoAccessScreen()));
      await tester.pump(); // resolve the overridden status future

      expect(find.textContaining('No active access'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Check again'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
    });

    testWidgets('is non-dismissable (PopScope blocks back)', (tester) async {
      await tester.pumpWidget(_scope(const NoAccessScreen()));
      await tester.pump();

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });
}
