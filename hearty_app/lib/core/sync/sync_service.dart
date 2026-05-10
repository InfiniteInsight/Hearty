import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_interceptor.dart';
import '../offline/offline_database.dart';

const kSyncTaskName = 'hearty_sync';
const kSyncTaskTag = 'com.hearty.app.sync';
const _maxRetries = 5;

const _kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class SyncService {
  SyncService(this._db, this._dio, this._ref);

  final OfflineDatabase _db;
  final Dio _dio;
  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _syncing = false;

  void start() {
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_onConnectivity);
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online && !_syncing) {
      await syncPending();
    }
  }

  /// Resets all failed entries to pending and runs a sync cycle.
  Future<void> retryFailed() async {
    await (_db.update(_db.offlineQueue)
          ..where((q) => q.status.equals('failed')))
        .write(const OfflineQueueCompanion(status: Value('pending')));
    await syncPending();
  }

  /// Permanently deletes all failed entries from the queue.
  Future<void> dismissFailed() async {
    await (_db.delete(_db.offlineQueue)
          ..where((q) => q.status.equals('failed')))
        .go();
  }

  /// Replays all pending queue entries in order.
  /// Called by connectivity listener and by the WorkManager background task.
  Future<void> syncPending() async {
    if (_syncing) return;
    _syncing = true;
    _ref.read(isSyncingProvider.notifier).state = true;
    try {
      final rows = await (_db.select(_db.offlineQueue)
            ..where((q) => q.status.equals('pending'))
            ..orderBy([(q) => OrderingTerm.asc(q.createdAt)]))
          .get();

      for (final row in rows) {
        await _syncRow(row);
      }
    } finally {
      _syncing = false;
      _ref.read(isSyncingProvider.notifier).state = false;
    }
  }

  Future<void> _syncRow(OfflineQueueData row) async {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(row.payload) as Map<String, dynamic>;
    } catch (_) {
      await (_db.update(_db.offlineQueue)..where((q) => q.id.equals(row.id)))
          .write(const OfflineQueueCompanion(status: Value('failed')));
      return;
    }

    await (_db.update(_db.offlineQueue)..where((q) => q.id.equals(row.id)))
        .write(const OfflineQueueCompanion(status: Value('syncing')));

    try {
      await _replayAction(row.actionType, payload);

      await (_db.delete(_db.offlineQueue)..where((q) => q.id.equals(row.id)))
          .go();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 500) {
        // 5xx — increment retry_count, mark pending again (up to max)
        final newRetry = row.retryCount + 1;
        await (_db.update(_db.offlineQueue)
              ..where((q) => q.id.equals(row.id)))
            .write(
          OfflineQueueCompanion(
            retryCount: Value(newRetry),
            status: Value(newRetry > _maxRetries ? 'failed' : 'pending'),
          ),
        );
      } else {
        // Non-5xx (validation error, etc.) — mark failed immediately
        await (_db.update(_db.offlineQueue)
              ..where((q) => q.id.equals(row.id)))
            .write(
          const OfflineQueueCompanion(status: Value('failed')),
        );
      }
    } catch (_) {
      // Unexpected error (including network errors / SocketException) — revert
      // to pending so next connectivity event retries.
      await (_db.update(_db.offlineQueue)..where((q) => q.id.equals(row.id)))
          .write(
        const OfflineQueueCompanion(status: Value('pending')),
      );
    }
  }

  /// Posts queued payloads directly via Dio, bypassing HeartyApiClient.
  ///
  /// HeartyApiClient's write methods swallow OfflineException and 5xx errors
  /// by transparently re-queuing them. That would silently reset retryCount on
  /// every sync cycle and prevent entries from ever reaching 'failed' status.
  /// Using raw Dio calls lets SyncService observe the real HTTP outcome.
  Future<void> _replayAction(
      String actionType, Map<String, dynamic> payload) async {
    switch (actionType) {
      case 'log_meal':
        await _dio.post<Map<String, dynamic>>('/api/meals', data: payload);
      case 'log_symptom':
        await _dio.post<List<dynamic>>('/api/symptoms', data: payload);
      case 'log_wellbeing':
        await _dio.post<Map<String, dynamic>>('/api/wellbeing', data: payload);
    }
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(offlineDatabaseProvider);
  final dio = Dio(BaseOptions(
    baseUrl: _kBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));
  dio.interceptors.add(AuthInterceptor());
  ref.onDispose(dio.close);

  final service = SyncService(db, dio, ref);
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

/// Count of pending queue entries — used by the UI offline chip.
final pendingQueueCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(offlineDatabaseProvider);
  return (db.select(db.offlineQueue)
        ..where((q) => q.status.equals('pending')))
      .watch()
      .map((rows) => rows.length);
});

/// True if any queue entries have status 'failed'.
final hasFailedQueueEntriesProvider = StreamProvider<bool>((ref) {
  final db = ref.watch(offlineDatabaseProvider);
  return (db.select(db.offlineQueue)
        ..where((q) => q.status.equals('failed')))
      .watch()
      .map((rows) => rows.isNotEmpty);
});

/// True if sync is currently in progress (set by syncPending).
final isSyncingProvider = StateProvider<bool>((ref) => false);
