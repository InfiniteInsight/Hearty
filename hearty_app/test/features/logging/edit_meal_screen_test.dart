import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/meal_log.dart';
import 'package:hearty_app/core/offline/local_meal_dao.dart';
import 'package:hearty_app/core/offline/offline_database.dart';
import 'package:hearty_app/features/logging/screens/edit_meal_screen.dart';

/// Records the [updateMeal] arguments so the foods dirty-tracking contract can
/// be asserted; everything else is a no-op (mirrors the photo widget-test
/// harness which drives screens through an overridden client provider).
class _FakeHeartyApiClient implements HeartyApiClient {
  String? lastDescription;
  List<String>? lastFoods;
  bool updateCalled = false;

  @override
  Future<MealLog> updateMeal(
    String id,
    String description, {
    List<String>? foods,
  }) async {
    updateCalled = true;
    lastDescription = description;
    lastFoods = foods;
    return MealLog(
      id: id,
      description: description,
      mealType: 'other',
      foods: foods ?? const [],
      loggedAt: DateTime(2026, 6, 20),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeHeartyApiClient api;
  late OfflineDatabase db;

  setUp(() {
    api = _FakeHeartyApiClient();
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<String> initialFoods,
  }) async {
    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(
          path: '/edit',
          builder: (context, state) => EditMealScreen(
            id: 'meal-1',
            initialDescription: 'Lunch',
            initialFoods: initialFoods,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          heartyApiClientProvider.overrideWithValue(api),
          localMealDaoProvider.overrideWithValue(LocalMealDao(db)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the identified foods as editable fields', (tester) async {
    await pumpScreen(tester, initialFoods: ['apple', 'banana']);

    expect(find.text('Foods identified'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'apple'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'banana'), findsOneWidget);
  });

  testWidgets('untouched foods -> Save sends foods: null (re-extract)',
      (tester) async {
    await pumpScreen(tester, initialFoods: ['apple', 'banana']);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.updateCalled, isTrue);
    expect(api.lastDescription, 'Lunch');
    expect(api.lastFoods, isNull);
  });

  testWidgets('edited foods -> Save sends the edited verbatim list',
      (tester) async {
    await pumpScreen(tester, initialFoods: ['apple', 'banana']);

    await tester.enterText(
      find.widgetWithText(TextField, 'apple'),
      'apricot',
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.updateCalled, isTrue);
    expect(api.lastFoods, ['apricot', 'banana']);
  });

  testWidgets('removing a food -> Save sends the shortened verbatim list',
      (tester) async {
    await pumpScreen(tester, initialFoods: ['apple', 'banana']);

    await tester.tap(find.byTooltip('Remove food').first);
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.lastFoods, ['banana']);
  });

  testWidgets('no foods section when the meal had no foods', (tester) async {
    await pumpScreen(tester, initialFoods: const []);

    expect(find.text('Foods identified'), findsNothing);
  });
}
