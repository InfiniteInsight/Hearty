import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/logging/widgets/editable_food_list.dart';

void main() {
  group('EditableFoodList', () {
    testWidgets('renders initialFoods as editable fields', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EditableFoodList(initialFoods: ['apple', 'banana']),
          ),
        ),
      );

      expect(find.widgetWithText(TextField, 'apple'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'banana'), findsOneWidget);
    });

    testWidgets('currentFoods returns trimmed, non-empty names in order',
        (tester) async {
      final key = GlobalKey<EditableFoodListState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditableFoodList(
              key: key,
              initialFoods: const ['  apple  ', 'banana', '   '],
            ),
          ),
        ),
      );

      expect(key.currentState!.currentFoods(), ['apple', 'banana']);
    });

    testWidgets('editing a field updates the collected list', (tester) async {
      final key = GlobalKey<EditableFoodListState>();
      List<String>? emitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditableFoodList(
              key: key,
              initialFoods: const ['apple'],
              onChanged: (foods) => emitted = foods,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'apple'),
        'apricot',
      );
      await tester.pump();

      expect(key.currentState!.currentFoods(), ['apricot']);
      expect(emitted, ['apricot']);
    });

    testWidgets('remove (✕) drops a row', (tester) async {
      final key = GlobalKey<EditableFoodListState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditableFoodList(
              key: key,
              initialFoods: const ['apple', 'banana'],
            ),
          ),
        ),
      );

      // Tap the remove button on the first row.
      await tester.tap(find.byTooltip('Remove food').first);
      await tester.pump();

      expect(find.widgetWithText(TextField, 'apple'), findsNothing);
      expect(find.widgetWithText(TextField, 'banana'), findsOneWidget);
      expect(key.currentState!.currentFoods(), ['banana']);
    });

    testWidgets('Add food appends an empty editable row', (tester) async {
      final key = GlobalKey<EditableFoodListState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditableFoodList(
              key: key,
              initialFoods: const ['apple'],
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.text('Add food'));
      await tester.pump();

      expect(find.byType(TextField), findsNWidgets(2));
      // The empty row contributes nothing until typed into.
      expect(key.currentState!.currentFoods(), ['apple']);

      await tester.enterText(find.byType(TextField).last, 'cherry');
      await tester.pump();
      expect(key.currentState!.currentFoods(), ['apple', 'cherry']);
    });
  });
}
