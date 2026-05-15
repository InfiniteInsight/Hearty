// lib/core/offline/local_trends_dao.dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/trends_data.dart';
import 'offline_database.dart';

class LocalTrendsDao extends DatabaseAccessor<OfflineDatabase> {
  LocalTrendsDao(super.db);

  Future<TrendsData?> read() async {
    final row =
        await (select(db.localTrendsCache)).getSingleOrNull();
    if (row == null) return null;
    return TrendsData.fromSignalsJson(
        jsonDecode(row.data) as Map<String, dynamic>);
  }

  Future<void> write(TrendsData trends) {
    return db.into(db.localTrendsCache).insertOnConflictUpdate(
          LocalTrendsCacheCompanion(
            id: const Value(1),
            data: Value(jsonEncode(trends.toJson())),
            cachedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  Future<DateTime?> cachedAt() async {
    final row =
        await (select(db.localTrendsCache)).getSingleOrNull();
    if (row == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(row.cachedAt);
  }
}

final localTrendsDaoProvider = Provider<LocalTrendsDao>((ref) {
  return LocalTrendsDao(ref.watch(offlineDatabaseProvider));
});
