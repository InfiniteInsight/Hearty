import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_interceptor.dart';
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

/// Central HTTP client for the Hearty REST API.
///
/// All methods surface [OfflineException] for connection failures and let
/// other [DioException]s propagate so callers can handle HTTP errors.
class HeartyApiClient {
  HeartyApiClient(this._dio);

  final Dio _dio;

  // ──────────────────────────────────────────────────────────────────────────
  // Internal helper — unwraps OfflineException from DioException.
  // ──────────────────────────────────────────────────────────────────────────

  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      if (e.error is OfflineException) throw e.error as OfflineException;
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Meals
  // ──────────────────────────────────────────────────────────────────────────

  Future<MealLog> logMeal({
    required String description,
    String? mealType,
  }) {
    return _call(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/meals',
        data: {
          'description': description,
          'meal_type': mealType,
          'input_method': 'voice',
        }..removeWhere((_, v) => v == null),
      );
      return MealLog.fromJson(response.data!);
    });
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
  }) {
    return _call(() async {
      final response = await _dio.post<List<dynamic>>(
        '/api/symptoms',
        data: {
          'raw_description': description,
          if (severity != null)
            'symptoms': [
              {'symptom_type': 'other', 'severity': severity}
            ],
        },
      );
      // Backend returns a list; return the first entry.
      final list = response.data!;
      return SymptomLog.fromJson(list.first as Map<String, dynamic>);
    });
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
  }) {
    return _call(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/wellbeing',
        data: <String, dynamic>{
          'energy_level': energy,
          'mood': mood,
          'notes': notes,
        }..removeWhere((_, v) => v == null),
      );
      return WellbeingLog.fromJson(response.data!);
    });
  }

  Future<List<WellbeingLog>> fetchWellbeing({
    DateTime? start,
    DateTime? end,
  }) {
    return _call(() async {
      final params = <String, dynamic>{};
      if (start != null) params['start_date'] = start.toIso8601String();
      if (end != null) params['end_date'] = end.toIso8601String();

      // Backend GET /api/wellbeing is not yet implemented; return empty list.
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
  final dio = Dio(BaseOptions(
    baseUrl: _kBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));
  dio.interceptors.add(AuthInterceptor());
  return HeartyApiClient(dio);
});
