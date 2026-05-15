// lib/core/offline/local_preferences_dao.dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/user_preferences.dart';
import 'offline_database.dart';

class LocalPreferencesDao extends DatabaseAccessor<OfflineDatabase> {
  LocalPreferencesDao(super.db);

  Future<UserPreferences?> read() async {
    final row =
        await (select(db.localPreferences)).getSingleOrNull();
    if (row == null) return null;
    return UserPreferences.fromJson(
        jsonDecode(row.data) as Map<String, dynamic>);
  }

  Future<void> write(UserPreferences prefs, {required String syncStatus}) {
    return db.into(db.localPreferences).insertOnConflictUpdate(
          LocalPreferencesCompanion(
            id: const Value(1),
            data: Value(jsonEncode(prefs.toJson())),
            syncStatus: Value(syncStatus),
          ),
        );
  }

  Future<void> markSynced() {
    return (update(db.localPreferences)..where((p) => p.id.equals(1)))
        .write(const LocalPreferencesCompanion(syncStatus: Value('synced')));
  }

  Future<bool> isPending() async {
    final status = await db.customSelect(
      'SELECT sync_status FROM local_preferences WHERE id = 1',
      readsFrom: {db.localPreferences},
    ).map((row) => row.read<String>('sync_status')).getSingleOrNull();
    return status == 'pending';
  }
}

final localPreferencesDaoProvider = Provider<LocalPreferencesDao>((ref) {
  return LocalPreferencesDao(ref.watch(offlineDatabaseProvider));
});
