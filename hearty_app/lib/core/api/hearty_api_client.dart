import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_interceptor.dart';
import 'models/meal_log.dart';
import 'models/symptom_log.dart';
import 'models/wellbeing_log.dart';
import 'models/wellbeing_period.dart';
import 'models/trends_data.dart';
import 'models/user_preferences.dart';
import 'offline_exception.dart';
import '../../features/photos/models/photo_upload_response.dart';
import '../../features/photos/models/photo_status_response.dart';

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
      final offline = e.error;
      if (offline is OfflineException) {
        Error.throwWithStackTrace(offline, e.stackTrace);
      }
      rethrow;
    }
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
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/meals',
      data: body,
    );
    return MealLog.fromJson(response.data!);
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
    final response = await _dio.post<List<dynamic>>(
      '/api/symptoms',
      data: body,
    );
    // Backend returns a list; return the first entry.
    final list = response.data!;
    return SymptomLog.fromJson(list.first as Map<String, dynamic>);
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
    WellbeingPeriod? period,
  }) async {
    final body = <String, dynamic>{
      'energy_level': energy,
      'mood': mood,
      'notes': notes,
      if (period != null) 'period': period.name,
    }..removeWhere((_, v) => v == null);
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/wellbeing',
      data: body,
    );
    return WellbeingLog.fromJson(response.data!);
  }

  Future<WellbeingLog> updateWellbeing(
    String id, {
    int? energy,
    int? mood,
    String? notes,
    WellbeingPeriod? period,
  }) async {
    final body = <String, dynamic>{};
    if (energy != null) body['energy_level'] = energy;
    if (mood != null) body['mood'] = mood;
    if (notes != null) body['notes'] = notes;
    if (period != null) body['period'] = period.name;
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/wellbeing/$id',
      data: body,
    );
    return WellbeingLog.fromJson(response.data!);
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
    DateTime? loggedAt,
  }) {
    return _call(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/chat',
        data: <String, dynamic>{
          'message': message,
          'health_context': healthContext,
          'logged_at': loggedAt?.toUtc().toIso8601String(),
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
  // Trends (Plan 11: Unified Signal Engine)
  // ──────────────────────────────────────────────────────────────────────────

  Future<TrendsData> fetchTrends({int days = 30}) {
    return _call(() async {
      final response = await _dio.get<Map<String, dynamic>>('/api/trends');
      return TrendsData.fromSignalsJson(response.data!);
    });
  }

  Future<Map<String, dynamic>> triggerAnalysis() {
    return _call(() async {
      final response = await _dio.post<Map<String, dynamic>>('/api/trends/analyze');
      return response.data!;
    });
  }

  Future<Map<String, dynamic>> getAnalyzeStatus() {
    return _call(() async {
      final response =
          await _dio.get<Map<String, dynamic>>('/api/trends/analyze/status');
      return response.data!;
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

  // ──────────────────────────────────────────────────────────────────────────
  // Photos
  // ──────────────────────────────────────────────────────────────────────────

  /// Uploads [file] to POST /api/photos as multipart/form-data with [type].
  /// Returns the initial upload response (status: 'pending').
  Future<PhotoUploadResponse> uploadPhoto({
    required File file,
    required String photoType, // pass PhotoType.apiValue
  }) {
    return _call(() async {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.uri.pathSegments.last,
        ),
        'type': photoType,
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/photos',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      return PhotoUploadResponse.fromJson(response.data!);
    });
  }

  /// Polls GET /api/photos/{id}/status for processing results.
  Future<PhotoStatusResponse> fetchPhotoStatus(String photoId) {
    return _call(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/photos/$photoId/status',
      );
      return PhotoStatusResponse.fromJson(response.data!);
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
  ref.onDispose(dio.close);
  return HeartyApiClient(dio);
});
