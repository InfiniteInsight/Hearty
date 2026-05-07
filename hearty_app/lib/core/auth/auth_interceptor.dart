import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/offline_exception.dart';

/// Injects the Supabase JWT into every outgoing request, and handles:
///   - 401 → token refresh → retry once
///   - connection errors → throws [OfflineException]
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Offline / connection errors — wrap into OfflineException.
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: const OfflineException(),
          type: err.type,
        ),
      );
      return;
    }

    // 401 → attempt token refresh → retry once.
    if (err.response?.statusCode == 401) {
      // Avoid infinite retry loops via a flag on requestOptions.extra.
      if (err.requestOptions.extra['_retried'] == true) {
        // Refresh failed or second 401 — sign out and rethrow.
        await Supabase.instance.client.auth.signOut();
        handler.next(err);
        return;
      }

      try {
        await Supabase.instance.client.auth.refreshSession();
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          await Supabase.instance.client.auth.signOut();
          handler.next(err);
          return;
        }

        // Retry the original request once with the new token.
        final opts = err.requestOptions
          ..headers['Authorization'] = 'Bearer ${session.accessToken}'
          ..extra['_retried'] = true;

        // Use a fresh Dio to avoid re-triggering this interceptor.
        final dio = Dio(BaseOptions(
          baseUrl: opts.baseUrl,
          connectTimeout: opts.connectTimeout,
          receiveTimeout: opts.receiveTimeout,
        ));
        final response = await dio.fetch(opts);
        handler.resolve(response);
      } catch (_) {
        await Supabase.instance.client.auth.signOut();
        handler.next(err);
      }
      return;
    }

    handler.next(err);
  }
}
