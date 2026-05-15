// lib/core/sync/sync_service.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hearty_api_client.dart';
import '../api/providers/meals_provider.dart' show SyncTrigger;
import '../auth/auth_interceptor.dart';
import '../offline/local_meal_dao.dart';
import '../offline/local_preferences_dao.dart';
import '../offline/local_symptom_dao.dart';
import '../offline/local_trends_dao.dart';
import '../offline/local_voice_queue_dao.dart';
import '../offline/local_wellbeing_dao.dart';
import '../offline/offline_database.dart';

const _kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

const _kAnalysisChannel = MethodChannel('com.hearty.app/analysis');

class SyncService implements SyncTrigger {
  SyncService(this._db, this._dio, this._ref);

  final OfflineDatabase _db;
  final Dio _dio;
  final Ref _ref;

  bool _syncing = false;
  bool _dirty = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicTimer;

  void start() {
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_onConnectivity);
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => schedule(),
    );
  }

  void dispose() {
    _connectivitySub?.cancel();
    _periodicTimer?.cancel();
  }

  @override
  void schedule() {
    if (_syncing) {
      _dirty = true;
    } else {
      _runCycle();
    }
  }

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online) schedule();
  }

  Future<void> _runCycle() async {
    if (_syncing) return;
    _syncing = true;
    _dirty = false;
    _ref.read(isSyncingProvider.notifier).state = true;

    try {
      final pushedAny = await _push();
      await _pull();
      if (pushedAny) _enqueueIdleAnalysis();
      await _prune();
    } finally {
      _syncing = false;
      _ref.read(isSyncingProvider.notifier).state = false;
      if (_dirty) _runCycle();
    }
  }

  // ── Push ────────────────────────────────────────────────────────────────────

  Future<bool> _push() async {
    bool pushedAny = false;
    pushedAny |= await _pushMeals();
    pushedAny |= await _pushSymptoms();
    pushedAny |= await _pushWellbeing();
    pushedAny |= await _pushPreferences();
    pushedAny |= await _pushVoiceQueue();
    return pushedAny;
  }

  Future<bool> _pushMeals() async {
    final dao = LocalMealDao(_db);
    final pending = await dao.getPending();
    bool pushed = false;

    for (final row in pending) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/meals',
          data: {
            'description': row.description,
            'meal_type': row.mealType,
          },
        );
        final serverId = response.data!['id'] as String;
        await dao.markSynced(row.id, serverId);
        pushed = true;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status != null && status >= 400 && status < 500) {
          await dao.markFailed(row.id);
        }
      } catch (_) {}
    }

    return pushed;
  }

  Future<bool> _pushSymptoms() async {
    final dao = LocalSymptomDao(_db);
    final pending = await dao.getPending();
    bool pushed = false;

    for (final row in pending) {
      try {
        final response = await _dio.post<dynamic>(
          '/api/symptoms',
          data: {
            'raw_description': row.description,
            'severity': row.severity,
          },
        );
        final list = response.data as List<dynamic>;
        final serverId = (list.first as Map<String, dynamic>)['id'] as String;
        await dao.markSynced(row.id, serverId);
        pushed = true;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status != null && status >= 400 && status < 500) {
          await dao.markFailed(row.id);
        }
      } catch (_) {}
    }

    return pushed;
  }

  Future<bool> _pushWellbeing() async {
    final dao = LocalWellbeingDao(_db);
    final pending = await dao.getPending();
    bool pushed = false;

    for (final row in pending) {
      try {
        if (row.serverId == null) {
          final response = await _dio.post<Map<String, dynamic>>(
            '/api/wellbeing',
            data: {
              'energy_level': row.energy,
              'mood': row.mood,
              if (row.notes != null) 'notes': row.notes,
              if (row.period != null) 'period': row.period,
            },
          );
          final serverId = response.data!['id'] as String;
          await dao.markSynced(row.id, serverId);
        } else {
          await _dio.patch<void>(
            '/api/wellbeing/${row.serverId}',
            data: {
              'energy_level': row.energy,
              'mood': row.mood,
              if (row.notes != null) 'notes': row.notes,
              if (row.period != null) 'period': row.period,
            },
          );
          await dao.markSynced(row.id, row.serverId!);
        }
        pushed = true;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status != null && status >= 400 && status < 500) {
          await dao.markFailed(row.id);
        }
      } catch (_) {}
    }

    return pushed;
  }

  Future<bool> _pushPreferences() async {
    final dao = LocalPreferencesDao(_db);
    if (!await dao.isPending()) return false;

    final prefs = await dao.read();
    if (prefs == null) return false;

    try {
      final client = _ref.read(heartyApiClientProvider);
      await client.savePreferences(prefs);
      await dao.markSynced();
      return true;
    } on DioException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _pushVoiceQueue() async {
    final dao = LocalVoiceQueueDao(_db);
    final pending = await dao.getPending();
    bool pushed = false;

    for (final row in pending) {
      try {
        await _ref.read(heartyApiClientProvider).chat(message: row.transcript);
        await dao.markDone(row.id);
        pushed = true;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status != null && status >= 400 && status < 500) {
          await dao.markFailed(row.id);
        }
        // Network error: leave as pending for next cycle
      } catch (_) {
        // Leave as pending
      }
    }

    return pushed;
  }

  // ── Pull ────────────────────────────────────────────────────────────────────

  Future<void> _pull() async {
    try {
      final client = _ref.read(heartyApiClientProvider);
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1).toUtc();

      final meals = await client.fetchMeals(start: yesterday, end: now.toUtc());
      final mealDao = LocalMealDao(_db);
      for (final m in meals) {
        await mealDao.upsertFromServer(m);
      }

      final symptoms = await client.fetchSymptoms(start: yesterday, end: now.toUtc());
      final symptomDao = LocalSymptomDao(_db);
      for (final s in symptoms) {
        await symptomDao.upsertFromServer(s);
      }

      final wellbeing = await client.fetchWellbeing(start: yesterday, end: now.toUtc());
      final wellbeingDao = LocalWellbeingDao(_db);
      for (final w in wellbeing) {
        await wellbeingDao.upsertFromServer(w);
      }

      final prefDao = LocalPreferencesDao(_db);
      if (!await prefDao.isPending()) {
        try {
          final prefs = await client.fetchPreferences();
          await prefDao.write(prefs, syncStatus: 'synced');
        } catch (_) {}
      }

      try {
        final trends = await client.fetchTrends();
        await LocalTrendsDao(_db).write(trends);
      } catch (_) {}
    } catch (_) {
      // Pull failure is non-fatal
    }
  }

  // ── Prune ───────────────────────────────────────────────────────────────────

  Future<void> _prune() async {
    await LocalMealDao(_db).pruneOldSynced();
    await LocalSymptomDao(_db).pruneOldSynced();
    await LocalWellbeingDao(_db).pruneOldSynced();
  }

  // ── Analysis Trigger ────────────────────────────────────────────────────────

  void _enqueueIdleAnalysis() {
    _kAnalysisChannel.invokeMethod<void>('enqueueIdleAnalysis').ignore();
  }

  // ── Public Actions ───────────────────────────────────────────────────────────

  Future<void> retryFailed() async {
    await (_db.update(_db.localMeals)
          ..where((m) => m.syncStatus.equals('failed')))
        .write(const LocalMealsCompanion(syncStatus: Value('pending')));
    await (_db.update(_db.localSymptoms)
          ..where((s) => s.syncStatus.equals('failed')))
        .write(const LocalSymptomsCompanion(syncStatus: Value('pending')));
    await (_db.update(_db.localWellbeing)
          ..where((w) => w.syncStatus.equals('failed')))
        .write(const LocalWellbeingCompanion(syncStatus: Value('pending')));
    schedule();
  }

  Future<void> dismissFailed() async {
    await (_db.delete(_db.localMeals)
          ..where((m) => m.syncStatus.equals('failed')))
        .go();
    await (_db.delete(_db.localSymptoms)
          ..where((s) => s.syncStatus.equals('failed')))
        .go();
    await (_db.delete(_db.localWellbeing)
          ..where((w) => w.syncStatus.equals('failed')))
        .go();
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

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

final pendingQueueCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(offlineDatabaseProvider);
  return db.customSelect(
    'SELECT SUM(cnt) as total FROM ('
    '  SELECT COUNT(*) as cnt FROM local_meals WHERE sync_status = ?'
    '  UNION ALL SELECT COUNT(*) as cnt FROM local_symptoms WHERE sync_status = ?'
    '  UNION ALL SELECT COUNT(*) as cnt FROM local_wellbeing WHERE sync_status = ?'
    '  UNION ALL SELECT COUNT(*) as cnt FROM local_preferences WHERE sync_status = ?'
    ')',
    variables: [
      Variable<String>('pending'),
      Variable<String>('pending'),
      Variable<String>('pending'),
      Variable<String>('pending'),
    ],
    readsFrom: {
      db.localMeals,
      db.localSymptoms,
      db.localWellbeing,
      db.localPreferences,
    },
  ).watchSingle().map((row) => row.read<int>('total'));
});

final hasFailedQueueEntriesProvider = StreamProvider<bool>((ref) {
  final db = ref.watch(offlineDatabaseProvider);
  return db.customSelect(
    'SELECT COUNT(*) > 0 as has_failed FROM ('
    '  SELECT 1 FROM local_meals WHERE sync_status = ?'
    '  UNION ALL SELECT 1 FROM local_symptoms WHERE sync_status = ?'
    '  UNION ALL SELECT 1 FROM local_wellbeing WHERE sync_status = ?'
    '  UNION ALL SELECT 1 FROM local_preferences WHERE sync_status = ?'
    ')',
    variables: [
      Variable<String>('failed'),
      Variable<String>('failed'),
      Variable<String>('failed'),
      Variable<String>('failed'),
    ],
    readsFrom: {
      db.localMeals,
      db.localSymptoms,
      db.localWellbeing,
      db.localPreferences,
    },
  ).watchSingle().map((row) => row.read<int>('has_failed') == 1);
});

final isSyncingProvider = StateProvider<bool>((ref) => false);
