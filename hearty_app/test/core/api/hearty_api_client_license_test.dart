import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/no_active_license_exception.dart';

/// Rejects every request with a canned [DioException] so we can exercise the
/// client's error translation without real HTTP. Mirrors the
/// `_CapturingInterceptor` style used by the other client tests.
class _RejectingInterceptor extends Interceptor {
  _RejectingInterceptor({required this.statusCode, required this.data});

  final int statusCode;
  final Object? data;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: statusCode,
          data: data,
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }
}

/// Resolves every request with a canned 200 body.
class _ResolvingInterceptor extends Interceptor {
  _ResolvingInterceptor(this.data);
  final Object? data;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<dynamic>(requestOptions: options, statusCode: 200, data: data),
    );
  }
}

HeartyApiClient _clientRejecting({required int statusCode, Object? data}) {
  final dio = Dio();
  dio.interceptors.add(_RejectingInterceptor(statusCode: statusCode, data: data));
  return HeartyApiClient(dio);
}

HeartyApiClient _clientResolving(Object? data) {
  final dio = Dio();
  dio.interceptors.add(_ResolvingInterceptor(data));
  return HeartyApiClient(dio);
}

void main() {
  group('HeartyApiClient 403 no_active_license mapping', () {
    test('403 {detail: no_active_license} surfaces as NoActiveLicenseException',
        () async {
      final client = _clientRejecting(
        statusCode: 403,
        data: <String, dynamic>{'detail': 'no_active_license'},
      );

      await expectLater(
        client.fetchMeals(),
        throwsA(isA<NoActiveLicenseException>()),
      );
    });

    test('other 403 detail propagates as DioException', () async {
      final client = _clientRejecting(
        statusCode: 403,
        data: <String, dynamic>{'detail': 'something_else'},
      );

      await expectLater(
        client.fetchMeals(),
        throwsA(isA<DioException>()),
      );
    });

    test('non-403 error propagates as DioException', () async {
      final client = _clientRejecting(
        statusCode: 500,
        data: <String, dynamic>{'detail': 'no_active_license'},
      );

      await expectLater(
        client.fetchMeals(),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('HeartyApiClient licenseStatus', () {
    test('GET /api/license/status returns the status string', () async {
      final client = _clientResolving(<String, dynamic>{
        'status': 'active',
        'expires_at': null,
      });

      expect(await client.licenseStatus(), 'active');
    });
  });
}
