// test/core/offline/local_meal_dao_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/meal_log.dart';
import 'package:hearty_app/core/offline/local_meal_dao.dart';
import 'package:hearty_app/core/offline/offline_database.dart';

OfflineDatabase _makeDb() => OfflineDatabase.forTesting(NativeDatabase.memory());

void main() {
  late OfflineDatabase db;
  late LocalMealDao dao;

  setUp(() {
    db = _makeDb();
    dao = LocalMealDao(db);
  });

  tearDown(() => db.close());

  test('insert and watchToday emits the new meal', () async {
    final now = DateTime.now();
    await dao.insertLocal(
      localId: 'uuid-1',
      description: 'Oatmeal',
      mealType: 'breakfast',
      foods: ['oats', 'milk'],
      loggedAt: now,
    );

    final meals = await dao.watchToday().first;
    expect(meals.length, 1);
    expect(meals.first.id, 'uuid-1');
    expect(meals.first.description, 'Oatmeal');
    expect(meals.first.foods, ['oats', 'milk']);
  });

  test('markSynced sets serverId and syncStatus', () async {
    await dao.insertLocal(
      localId: 'uuid-2',
      description: 'Lunch',
      mealType: 'lunch',
      foods: [],
      loggedAt: DateTime.now(),
    );
    await dao.markSynced('uuid-2', 'server-id-99');

    final rows = await db.select(db.localMeals).get();
    expect(rows.first.serverId, 'server-id-99');
    expect(rows.first.syncStatus, 'synced');
  });

  test('upsertFromServer skips pending local records', () async {
    final now = DateTime.now();
    await dao.insertLocal(
      localId: 'uuid-3',
      description: 'Local pending',
      mealType: 'dinner',
      foods: [],
      loggedAt: now,
    );
    await dao.markSynced('uuid-3', 'srv-3');
    // Manually set back to pending to simulate unsent change
    await (db.update(db.localMeals)..where((m) => m.id.equals('uuid-3')))
        .write(const LocalMealsCompanion(syncStatus: Value('pending')));

    final serverMeal = MealLog(
      id: 'srv-3',
      description: 'Server version',
      mealType: 'dinner',
      foods: ['server food'],
      loggedAt: now,
    );
    await dao.upsertFromServer(serverMeal);

    final row = await (db.select(db.localMeals)
          ..where((m) => m.id.equals('uuid-3')))
        .getSingle();
    expect(row.description, 'Local pending'); // not overwritten
  });

  test('getPending returns only pending rows', () async {
    await dao.insertLocal(
      localId: 'p1',
      description: 'Pending',
      mealType: 'other',
      foods: [],
      loggedAt: DateTime.now(),
    );
    await dao.insertLocal(
      localId: 'p2',
      description: 'Also pending',
      mealType: 'other',
      foods: [],
      loggedAt: DateTime.now(),
    );
    await dao.markSynced('p2', 'srv-p2');

    final pending = await dao.getPending();
    expect(pending.length, 1);
    expect(pending.first.id, 'p1');
  });

  test('pruneOldSynced removes synced records older than 7 days', () async {
    final old = DateTime.now().subtract(const Duration(days: 8));
    final recent = DateTime.now();

    await dao.insertLocal(
      localId: 'old-1',
      description: 'Old synced',
      mealType: 'other',
      foods: [],
      loggedAt: old,
    );
    await dao.markSynced('old-1', 'srv-old');

    await dao.insertLocal(
      localId: 'new-1',
      description: 'Recent synced',
      mealType: 'other',
      foods: [],
      loggedAt: recent,
    );
    await dao.markSynced('new-1', 'srv-new');

    await dao.pruneOldSynced();

    final remaining = await db.select(db.localMeals).get();
    expect(remaining.length, 1);
    expect(remaining.first.id, 'new-1');
  });
}
