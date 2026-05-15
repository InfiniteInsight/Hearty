// lib/core/offline/local_voice_queue_dao.dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_database.dart';

class LocalVoiceQueueDao extends DatabaseAccessor<OfflineDatabase> {
  LocalVoiceQueueDao(super.db);

  Future<void> insertPending({
    required String id,
    required String transcript,
    required DateTime loggedAt,
  }) {
    return db.into(db.localVoiceQueue).insert(
          LocalVoiceQueueCompanion(
            id: Value(id),
            transcript: Value(transcript),
            loggedAt: Value(loggedAt.millisecondsSinceEpoch),
            syncStatus: const Value('pending'),
          ),
        );
  }

  Future<List<LocalVoiceQueueData>> getPending() {
    return (select(db.localVoiceQueue)
          ..where((v) => v.syncStatus.equals('pending'))
          ..orderBy([(v) => OrderingTerm.asc(v.loggedAt)]))
        .get();
  }

  Future<void> markDone(String id) {
    return (delete(db.localVoiceQueue)..where((v) => v.id.equals(id))).go();
  }

  Future<void> markFailed(String id) {
    return (update(db.localVoiceQueue)..where((v) => v.id.equals(id)))
        .write(const LocalVoiceQueueCompanion(syncStatus: Value('failed')));
  }
}

final localVoiceQueueDaoProvider = Provider<LocalVoiceQueueDao>((ref) {
  return LocalVoiceQueueDao(ref.watch(offlineDatabaseProvider));
});
