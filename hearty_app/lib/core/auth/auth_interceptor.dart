import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Injects the Supabase JWT into every outgoing request.
///
/// Full token-refresh + retry logic is deferred to Phase 5 when the
/// centralised API client is built.
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
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // On 401: trigger token refresh, then retry once.
    // Full retry logic comes in Phase 5 when the API client is built.
    handler.next(err);
  }
}
