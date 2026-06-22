import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';

/// Captures the outgoing request and short-circuits it with a canned response,
/// so no real HTTP is performed. Mirrors the dependency-injection style the
/// repo already favours (no mock library is on the dev_dependencies).
class _CapturingInterceptor extends Interceptor {
  _CapturingInterceptor(this.responseData);

  final Object? responseData;
  RequestOptions? lastRequest;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastRequest = options;
    handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: responseData,
      ),
    );
  }
}

({HeartyApiClient client, _CapturingInterceptor interceptor}) _build(
  Object? responseData,
) {
  final dio = Dio();
  final interceptor = _CapturingInterceptor(responseData);
  dio.interceptors.add(interceptor);
  return (client: HeartyApiClient(dio), interceptor: interceptor);
}

Map<String, dynamic> _mealResponse() => <String, dynamic>{
      'id': 'meal-1',
      'description': 'x',
      'meal_type': 'other',
      'foods': <dynamic>[],
      'logged_at': '2026-06-20T12:00:00Z',
    };

void main() {
  group('HeartyApiClient logMeal', () {
    test('sends foods and input_method when provided', () async {
      final harness = _build(_mealResponse());

      await harness.client.logMeal(
        description: 'x',
        foods: ['a', 'b'],
        inputMethod: 'photo',
      );

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/meals');
      expect(req.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      expect(body['description'], 'x');
      expect(body['foods'], ['a', 'b']);
      expect(body['input_method'], 'photo');
    });

    test('omits foods key and defaults input_method to voice', () async {
      final harness = _build(_mealResponse());

      await harness.client.logMeal(description: 'x');

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/meals');
      expect(req.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      expect(body['description'], 'x');
      expect(body.containsKey('foods'), isFalse);
      expect(body['input_method'], 'voice');
    });
  });
}
