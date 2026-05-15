// lib/core/offline/local_wellbeing_dao.dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/wellbeing_log.dart';
import '../api/models/wellbeing_period.dart';
import 'offline_database.dart';

class LocalWellbeingDao extends DatabaseAccessor<OfflineDatabase> {
  LocalWellbeingDao(super.db);

  Stream<List<WellbeingLog>> watchToday() {
    final now = DateTime.now();
    final startMs =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return (select(db.localWellbeing)
          ..where((w) => w.loggedAt.isBiggerOrEqualValue(startMs))
          ..orderBy([(w) => OrderingTerm.desc(w.loggedAt)]))
        .watch()
        .map((rows) => rows.map(WellbeingLog.fromLocal).toList());
  }

  Future<void> insertLocal({
    required String localId,
    required int energy,
    required int mood,
    String? notes,
    String? period,
    required DateTime loggedAt,
  }) {
    return db.into(db.localWellbeing).insert(
          LocalWellbeingCompanion(
            id: Value(localId),
            energy: Value(energy),
            mood: Value(mood),
            notes: Value(notes),
            period: Value(period),
            loggedAt: Value(loggedAt.millisecondsSinceEpoch),
            syncStatus: const Value('pending'),
          ),
        );
  }

  Future<void> updateLocal(
    String localId, {
    int? energy,
    int? mood,
    String? notes,
    WellbeingPeriod? period,
  }) async {
    final row = await (select(db.localWellbeing)
          ..where((w) => w.id.equals(localId)))
        .getSingle();
    await (update(db.localWellbeing)..where((w) => w.id.equals(localId)))
        .write(LocalWellbeingCompanion(
      energy: Value(energy ?? row.energy),
      mood: Value(mood ?? row.mood),
      notes: Value(notes ?? row.notes),
      period: Value(period?.name ?? row.period),
      syncStatus: const Value('pending'),
    ));
  }

  Future<List<LocalWellbeingData>> getPending() {
    return (select(db.localWellbeing)
          ..where((w) => w.syncStatus.equals('pending'))
          ..orderBy([(w) => OrderingTerm.asc(w.loggedAt)]))
        .get();
  }

  Future<void> markSynced(String localId, String serverId) {
    return (update(db.localWellbeing)..where((w) => w.id.equals(localId)))
        .write(LocalWellbeingCompanion(
      serverId: Value(serverId),
      syncStatus: const Value('synced'),
    ));
  }

  Future<void> markFailed(String localId) {
    return (update(db.localWellbeing)..where((w) => w.id.equals(localId)))
        .write(const LocalWellbeingCompanion(syncStatus: Value('failed')));
  }

  Future<void> upsertFromServer(WellbeingLog entry) async {
    final existing = await (select(db.localWellbeing)
          ..where((w) => w.serverId.equals(entry.id)))
        .getSingleOrNull();

    if (existing?.syncStatus == 'pending') return;

    if (existing != null) {
      await (update(db.localWellbeing)..where((w) => w.id.equals(existing.id)))
          .write(LocalWellbeingCompanion(
        energy: Value(entry.energy),
        mood: Value(entry.mood),
        notes: Value(entry.notes),
        period: Value(entry.period?.name),
        loggedAt: Value(entry.loggedAt.millisecondsSinceEpoch),
        syncStatus: const Value('synced'),
      ));
    } else {
      await db.into(db.localWellbeing).insertOnConflictUpdate(
            LocalWellbeingCompanion(
              id: Value(entry.id),
              serverId: Value(entry.id),
              energy: Value(entry.energy),
              mood: Value(entry.mood),
              notes: Value(entry.notes),
              period: Value(entry.period?.name),
              loggedAt: Value(entry.loggedAt.millisecondsSinceEpoch),
              syncStatus: const Value('synced'),
            ),
          );
    }
  }

  Future<void> pruneOldSynced() {
    final cutoffMs = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    return (delete(db.localWellbeing)
          ..where((w) =>
              w.syncStatus.equals('synced') &
              w.loggedAt.isSmallerThanValue(cutoffMs)))
        .go();
  }
}

final localWellbeingDaoProvider = Provider<LocalWellbeingDao>((ref) {
  return LocalWellbeingDao(ref.watch(offlineDatabaseProvider));
});
