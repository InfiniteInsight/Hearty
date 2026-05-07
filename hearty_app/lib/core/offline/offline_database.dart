import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'offline_database.g.dart';

class OfflineQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get actionType => text()(); // 'log_meal' | 'log_symptom' | 'log_wellbeing'
  TextColumn get payload => text()();    // JSON-encoded request body
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  // status: 'pending' | 'syncing' | 'failed'
}

@DriftDatabase(tables: [OfflineQueue])
class OfflineDatabase extends _$OfflineDatabase {
  OfflineDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'hearty_offline');
  }
}

final offlineDatabaseProvider = Provider<OfflineDatabase>((ref) {
  final db = OfflineDatabase();
  ref.onDispose(db.close);
  return db;
});
