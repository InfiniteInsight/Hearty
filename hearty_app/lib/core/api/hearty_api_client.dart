import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_interceptor.dart';
import 'models/chat_result.dart';
import 'models/meal_log.dart';
import 'models/symptom_log.dart';
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

  Future<MealLog> updateMeal(String id, String description) async {
    return _call(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/api/meals/$id',
        data: {'description': description},
      );
      return MealLog.fromJson(response.data!);
    });
  }

  Future<void> deleteMeal(String id) async {
    await _call(() async {
      await _dio.delete<void>('/api/meals/$id');
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

  Future<SymptomLog> updateSymptom(
    String id,
    String description, {
    int? severity,
    int? onsetMinutes,
  }) async {
    return _call(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/api/symptoms/$id',
        data: <String, dynamic>{
          'description': description,
          'severity': ?severity,
          'onset_minutes': ?onsetMinutes,
        },
      );
      return SymptomLog.fromJson(response.data!);
    });
  }

  Future<void> deleteSymptom(String id) async {
    await _call(() async {
      await _dio.delete<void>('/api/symptoms/$id');
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Chat (voice AI)
  // ──────────────────────────────────────────────────────────────────────────

  Future<ChatResult> chat({
    required String message,
    String? mealId,
    List<Map<String, String>>? history,
    Map<String, dynamic>? healthContext,
    DateTime? loggedAt,
    String conversationStyle = 'warm',
    bool symptomFollowUp = false,
  }) {
    return _call(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/chat',
        data: <String, dynamic>{
          'message': message,
          'meal_id': ?mealId,
          'history': ?history,
          'health_context': healthContext,
          'logged_at': loggedAt?.toUtc().toIso8601String(),
          'conversation_style': conversationStyle,
          'symptom_followup': symptomFollowUp,
        }..removeWhere((_, v) => v == null),
      );
      return ChatResult.fromJson(response.data!);
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
