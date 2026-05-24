// lib/core/offline/local_symptom_dao.dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/symptom_log.dart';
import 'offline_database.dart';

class LocalSymptomDao extends DatabaseAccessor<OfflineDatabase> {
  LocalSymptomDao(super.db);

  Stream<List<SymptomLog>> watchToday() {
    final now = DateTime.now();
    final startMs =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return (select(db.localSymptoms)
          ..where((s) => s.loggedAt.isBiggerOrEqualValue(startMs))
          ..orderBy([(s) => OrderingTerm.desc(s.loggedAt)]))
        .watch()
        .map((rows) => rows.map(SymptomLog.fromLocal).toList());
  }

  Future<void> insertLocal({
    required String localId,
    required String description,
    required int severity,
    required DateTime loggedAt,
    String? linkedMealId,
  }) {
    return db.into(db.localSymptoms).insert(
          LocalSymptomsCompanion(
            id: Value(localId),
            description: Value(description),
            severity: Value(severity),
            linkedMealId: Value(linkedMealId),
            loggedAt: Value(loggedAt.millisecondsSinceEpoch),
            syncStatus: const Value('pending'),
          ),
        );
  }

  Future<List<LocalSymptom>> getPending() {
    return (select(db.localSymptoms)
          ..where((s) => s.syncStatus.equals('pending'))
          ..orderBy([(s) => OrderingTerm.asc(s.loggedAt)]))
        .get();
  }

  Future<void> markSynced(String localId, String serverId) {
    return (update(db.localSymptoms)..where((s) => s.id.equals(localId)))
        .write(LocalSymptomsCompanion(
      serverId: Value(serverId),
      syncStatus: const Value('synced'),
    ));
  }

  Future<void> markFailed(String localId) {
    return (update(db.localSymptoms)..where((s) => s.id.equals(localId)))
        .write(const LocalSymptomsCompanion(syncStatus: Value('failed')));
  }

  Future<void> upsertFromServer(SymptomLog symptom) async {
    final existing = await (select(db.localSymptoms)
          ..where((s) => s.serverId.equals(symptom.id)))
        .getSingleOrNull();

    if (existing?.syncStatus == 'pending') return;

    if (existing != null) {
      await (update(db.localSymptoms)..where((s) => s.id.equals(existing.id)))
          .write(LocalSymptomsCompanion(
        description: Value(symptom.description),
        severity: Value(symptom.severity),
        linkedMealId: Value(symptom.linkedMealId),
        loggedAt: Value(symptom.loggedAt.millisecondsSinceEpoch),
        syncStatus: const Value('synced'),
      ));
    } else {
      await db.into(db.localSymptoms).insertOnConflictUpdate(
            LocalSymptomsCompanion(
              id: Value(symptom.id),
              serverId: Value(symptom.id),
              description: Value(symptom.description),
              severity: Value(symptom.severity),
              linkedMealId: Value(symptom.linkedMealId),
              loggedAt: Value(symptom.loggedAt.millisecondsSinceEpoch),
              syncStatus: const Value('synced'),
            ),
          );
    }
  }

  Future<void> deleteByServerId(String serverId) {
    return (delete(db.localSymptoms)..where((s) => s.serverId.equals(serverId))).go();
  }

  Future<void> pruneOldSynced() {
    final cutoffMs = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    return (delete(db.localSymptoms)
          ..where((s) =>
              s.syncStatus.equals('synced') &
              s.loggedAt.isSmallerThanValue(cutoffMs)))
        .go();
  }
}

final localSymptomDaoProvider = Provider<LocalSymptomDao>((ref) {
  return LocalSymptomDao(ref.watch(offlineDatabaseProvider));
});
