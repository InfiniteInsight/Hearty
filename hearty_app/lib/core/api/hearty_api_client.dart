import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_interceptor.dart';
import '../offline/offline_database.dart';
import 'models/meal_log.dart';
import 'models/symptom_log.dart';
import 'models/wellbeing_log.dart';
import 'models/trends_data.dart';
import 'models/user_preferences.dart';
import 'offline_exception.dart';

const _kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

const _uuid = Uuid();

/// Central HTTP client for the Hearty REST API.
///
/// All methods surface [OfflineException] for connection failures and let
/// other [DioException]s propagate so callers can handle HTTP errors.
///
/// Write methods ([logMeal], [logSymptom], [logWellbeing]) catch
/// [OfflineException] **and** 5xx server errors transparently: the operation
/// is written to the offline queue and a synthetic model is returned so the
/// UI can display the entry immediately without knowing it was queued.
class HeartyApiClient {
  HeartyApiClient(this._dio, this._offlineDb);

  final Dio _dio;
  final OfflineDatabase _offlineDb;

  // ──────────────────────────────────────────────────────────────────────────
  // Internal helper — unwraps OfflineException from DioException.
  // ──────────────────────────────────────────────────────────────────────────

  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      final offline = e.error;
      if (offline is OfflineException) {
        Error.throwWithStackTrace(offline, e.stackTrace);
      }
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Offline queue helper
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _queueOffline(
      String actionType, Map<String, dynamic> payload) async {
    await _offlineDb.into(_offlineDb.offlineQueue).insert(
          OfflineQueueCompanion.insert(
            actionType: actionType,
            payload: jsonEncode(payload),
          ),
        );
  }

  /// Returns true if [e] should be treated as an offline / unavailable failure
  /// for write operations (connectivity loss OR 5xx server error).
  bool _shouldQueue(Object e) {
    if (e is OfflineException) return true;
    if (e is DioException) {
      if (e.error is OfflineException) return true;
      final status = e.response?.statusCode;
      if (status != null && status >= 500) return true;
    }
    return false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Meals
  // ──────────────────────────────────────────────────────────────────────────

  Future<MealLog> logMeal({
    required String description,
    String? mealType,
  }) async {
    final body = <String, dynamic>{
      'description': description,
      'meal_type': mealType,
      'input_method': 'voice',
    }..removeWhere((_, v) => v == null);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/meals',
        data: body,
      );
      return MealLog.fromJson(response.data!);
    } catch (e) {
      if (_shouldQueue(e)) {
        await _queueOffline('log_meal', body);
        return MealLog(
          id: _uuid.v4(),
          description: description,
          mealType: mealType ?? 'other',
          foods: [],
          loggedAt: DateTime.now(),
          claudeNote: null,
        );
      }
      rethrow;
    }
  }

  Future<List<MealLog>> fetchMeals({
    DateTime? start,
    DateTime? end,
    int limit = 50,
  }) {
    return _call(() async {
      final params = <String, dynamic>{'limit': limit};
      if (start != null) params['start_date'] = start.toIso8601String();
      if (end != null) params['end_date'] = end.toIso8601String();

      final response = await _dio.get<Map<String, dynamic>>(
        '/api/meals',
        queryParameters: params,
      );
      final data = response.data!;
      final meals = data['meals'] as List<dynamic>? ?? [];
      return meals
          .map((m) => MealLog.fromJson(m as Map<String, dynamic>))
          .toList();
    });
  }

  Future<MealLog> fetchMealById(String id) {
    return _call(() async {
      final response = await _dio.get<Map<String, dynamic>>('/api/meals/$id');
      return MealLog.fromJson(response.data!);
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Symptoms
  // ──────────────────────────────────────────────────────────────────────────

  Future<SymptomLog> logSymptom({
    required String description,
    int? severity,
  }) async {
    final body = <String, dynamic>{
      'raw_description': description,
      if (severity != null)
        'symptoms': [
          {'symptom_type': 'other', 'severity': severity}
        ],
    };
    try {
      final response = await _dio.post<List<dynamic>>(
        '/api/symptoms',
        data: body,
      );
      // Backend returns a list; return the first entry.
      final list = response.data!;
      return SymptomLog.fromJson(list.first as Map<String, dynamic>);
    } catch (e) {
      if (_shouldQueue(e)) {
        await _queueOffline('log_symptom', body);
        return SymptomLog(
          id: _uuid.v4(),
          description: description,
          severity: severity ?? 1,
          linkedMealId: null,
          loggedAt: DateTime.now(),
        );
      }
      rethrow;
    }
  }

  Future<List<SymptomLog>> fetchSymptoms({
    DateTime? start,
    DateTime? end,
  }) {
    return _call(() async {
      final params = <String, dynamic>{};
      if (start != null) params['start_date'] = start.toIso8601String();
      if (end != null) params['end_date'] = end.toIso8601String();

      final response = await _dio.get<List<dynamic>>(
        '/api/symptoms',
        queryParameters: params,
      );
      return (response.data ?? [])
          .map((s) => SymptomLog.fromJson(s as Map<String, dynamic>))
          .toList();
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Wellbeing
  // ──────────────────────────────────────────────────────────────────────────

  Future<WellbeingLog> logWellbeing({
    int? energy,
    int? mood,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'energy_level': energy,
      'mood': mood,
      'notes': notes,
    }..removeWhere((_, v) => v == null);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/wellbeing',
        data: body,
      );
      return WellbeingLog.fromJson(response.data!);
    } catch (e) {
      if (_shouldQueue(e)) {
        await _queueOffline('log_wellbeing', body);
        return WellbeingLog(
          id: _uuid.v4(),
          energy: energy ?? 3,
          mood: mood ?? 3,
          notes: notes,
          loggedAt: DateTime.now(),
        );
      }
      rethrow;
    }
  }

  Future<List<WellbeingLog>> fetchWellbeing({
    DateTime? start,
    DateTime? end,
  }) {
    return _call(() async {
      final params = <String, dynamic>{};
      if (start != null) params['start_date'] = start.toIso8601String();
      if (end != null) params['end_date'] = end.toIso8601String();

      final response = await _dio.get<List<dynamic>>(
        '/api/wellbeing',
        queryParameters: params,
      );
      return (response.data ?? [])
          .map((w) => WellbeingLog.fromJson(w as Map<String, dynamic>))
          .toList();
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Chat (voice AI)
  // ──────────────────────────────────────────────────────────────────────────

  Future<String> chat({
    required String message,
    Map<String, dynamic>? healthContext,
  }) {
    return _call(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/chat',
        data: <String, dynamic>{
          'message': message,
          'health_context': healthContext,
        }..removeWhere((_, v) => v == null),
      );
      final data = response.data!;
      return (data['reply'] as String?) ??
          (data['response'] as String?) ??
          (data['message'] as String?) ??
          '';
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Trends
  // ──────────────────────────────────────────────────────────────────────────

  Future<TrendsData> fetchTrends({int days = 30}) {
    return _call(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/trends',
        queryParameters: {'analysis_period_days': days},
      );
      return TrendsData.fromJson(response.data!);
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Preferences
  // ──────────────────────────────────────────────────────────────────────────

  Future<UserPreferences> fetchPreferences() {
    return _call(() async {
      final response = await _dio.get<Map<String, dynamic>>('/api/preferences');
      return UserPreferences.fromJson(response.data!);
    });
  }

  Future<UserPreferences> savePreferences(UserPreferences prefs) {
    return _call(() async {
      final response = await _dio.put<Map<String, dynamic>>(
        '/api/preferences',
        data: prefs.toJson(),
      );
      return UserPreferences.fromJson(response.data!);
    });
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Riverpod provider
// ────────────────────────────────────────────────────────────────────────────

final heartyApiClientProvider = Provider<HeartyApiClient>((ref) {
  final db = ref.watch(offlineDatabaseProvider);
  final dio = Dio(BaseOptions(
    baseUrl: _kBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));
  dio.interceptors.add(AuthInterceptor());
  ref.onDispose(dio.close);
  return HeartyApiClient(dio, db);
});
