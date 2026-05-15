// lib/core/offline/offline_database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'offline_database.g.dart';

class LocalMeals extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get description => text()();
  TextColumn get mealType => text()();
  TextColumn get foods => text()(); // JSON array of strings
  IntColumn get loggedAt => integer()(); // unix ms
  TextColumn get claudeNote => text().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSymptoms extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get description => text()();
  IntColumn get severity => integer().withDefault(const Constant(1))();
  TextColumn get linkedMealId => text().nullable()();
  IntColumn get loggedAt => integer()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalWellbeing extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  IntColumn get energy => integer().withDefault(const Constant(3))();
  IntColumn get mood => integer().withDefault(const Constant(3))();
  TextColumn get notes => text().nullable()();
  TextColumn get period => text().nullable()();
  IntColumn get loggedAt => integer()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalPreferences extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get data => text()(); // JSON blob of UserPreferences
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalTrendsCache extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get data => text()(); // JSON blob of TrendsData
  IntColumn get cachedAt => integer()(); // unix ms

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  LocalMeals,
  LocalSymptoms,
  LocalWellbeing,
  LocalPreferences,
  LocalTrendsCache,
])
class OfflineDatabase extends _$OfflineDatabase {
  OfflineDatabase() : super(_openConnection());
  OfflineDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from == 1) {
            await customStatement('DROP TABLE IF EXISTS offline_queue');
            await migrator.createTable(localMeals);
            await migrator.createTable(localSymptoms);
            await migrator.createTable(localWellbeing);
            await migrator.createTable(localPreferences);
            await migrator.createTable(localTrendsCache);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'hearty_offline');
  }
}

final offlineDatabaseProvider = Provider<OfflineDatabase>((ref) {
  final db = OfflineDatabase();
  ref.onDispose(db.close);
  return db;
});
