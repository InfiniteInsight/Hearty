// lib/core/offline/local_meal_dao.dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/meal_log.dart';
import 'offline_database.dart';

class LocalMealDao extends DatabaseAccessor<OfflineDatabase> {
  LocalMealDao(super.db);

  Stream<List<MealLog>> watchToday() {
    final now = DateTime.now();
    final startMs =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return (select(db.localMeals)
          ..where((m) => m.loggedAt.isBiggerOrEqualValue(startMs))
          ..orderBy([(m) => OrderingTerm.desc(m.loggedAt)]))
        .watch()
        .map((rows) => rows.map(MealLog.fromLocal).toList());
  }

  Future<void> insertLocal({
    required String localId,
    required String description,
    required String mealType,
    required List<String> foods,
    required DateTime loggedAt,
    String? claudeNote,
  }) {
    return db.into(db.localMeals).insert(
          LocalMealsCompanion(
            id: Value(localId),
            description: Value(description),
            mealType: Value(mealType),
            foods: Value(jsonEncode(foods)),
            loggedAt: Value(loggedAt.millisecondsSinceEpoch),
            claudeNote: Value(claudeNote),
            syncStatus: const Value('pending'),
          ),
        );
  }

  Future<List<LocalMeal>> getPending() {
    return (select(db.localMeals)
          ..where((m) => m.syncStatus.equals('pending'))
          ..orderBy([(m) => OrderingTerm.asc(m.loggedAt)]))
        .get();
  }

  Future<void> markSynced(String localId, String serverId) {
    return (update(db.localMeals)..where((m) => m.id.equals(localId))).write(
      LocalMealsCompanion(
        serverId: Value(serverId),
        syncStatus: const Value('synced'),
      ),
    );
  }

  Future<void> markFailed(String localId) {
    return (update(db.localMeals)..where((m) => m.id.equals(localId)))
        .write(const LocalMealsCompanion(syncStatus: Value('failed')));
  }

  Future<void> upsertFromServer(MealLog meal) async {
    final existing = await (select(db.localMeals)
          ..where((m) => m.serverId.equals(meal.id)))
        .getSingleOrNull();

    if (existing?.syncStatus == 'pending') return;

    if (existing != null) {
      await (update(db.localMeals)..where((m) => m.id.equals(existing.id)))
          .write(LocalMealsCompanion(
        description: Value(meal.description),
        mealType: Value(meal.mealType),
        foods: Value(jsonEncode(meal.foods)),
        loggedAt: Value(meal.loggedAt.millisecondsSinceEpoch),
        claudeNote: Value(meal.claudeNote),
        syncStatus: const Value('synced'),
      ));
    } else {
      await db.into(db.localMeals).insertOnConflictUpdate(
            LocalMealsCompanion(
              id: Value(meal.id),
              serverId: Value(meal.id),
              description: Value(meal.description),
              mealType: Value(meal.mealType),
              foods: Value(jsonEncode(meal.foods)),
              loggedAt: Value(meal.loggedAt.millisecondsSinceEpoch),
              claudeNote: Value(meal.claudeNote),
              syncStatus: const Value('synced'),
            ),
          );
    }
  }

  Future<void> pruneOldSynced() {
    final cutoffMs = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    return (delete(db.localMeals)
          ..where((m) =>
              m.syncStatus.equals('synced') &
              m.loggedAt.isSmallerThanValue(cutoffMs)))
        .go();
  }
}

final localMealDaoProvider = Provider<LocalMealDao>((ref) {
  return LocalMealDao(ref.watch(offlineDatabaseProvider));
});
