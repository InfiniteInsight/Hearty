import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';

/// Captures the outgoing request and short-circuits it with a canned response,
/// so no real HTTP is performed. Mirrors the interceptor-based DI style the
/// repo already favours (see hearty_api_client_trends_test.dart).
class _CapturingInterceptor extends Interceptor {
  _CapturingInterceptor(this.responseData, {this.statusCode = 200});

  final Object? responseData;
  final int statusCode;
  RequestOptions? lastRequest;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastRequest = options;
    handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        statusCode: statusCode,
        data: responseData,
      ),
    );
  }
}

({HeartyApiClient client, _CapturingInterceptor interceptor}) _build(
  Object? responseData, {
  int statusCode = 200,
}) {
  final dio = Dio();
  final interceptor =
      _CapturingInterceptor(responseData, statusCode: statusCode);
  dio.interceptors.add(interceptor);
  return (client: HeartyApiClient(dio), interceptor: interceptor);
}

void main() {
  group('HeartyApiClient photos', () {
    test('uploadFoodPhoto posts multipart to /api/photos and returns the id',
        () async {
      final harness = _build(<String, dynamic>{
        'id': 'photo-123',
        'type': 'food_plate',
        'status': 'processing',
        'meal_id': null,
        'message': 'Processing your photo…',
      });

      final id = await harness.client.uploadFoodPhoto(
        bytes: const [1, 2, 3, 4],
        filename: 'plate.jpg',
        mealId: 'meal-9',
      );

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/photos');
      expect(req.method, 'POST');
      expect(req.data, isA<FormData>());

      final form = req.data as FormData;
      // File part sent under the `file` field.
      expect(form.files.map((e) => e.key), contains('file'));
      expect(form.files.first.value.filename, 'plate.jpg');
      // Form fields: type defaults to food_plate, meal_id passed through.
      final fields = {for (final f in form.fields) f.key: f.value};
      expect(fields['type'], 'food_plate');
      expect(fields['meal_id'], 'meal-9');

      expect(id, 'photo-123');
    });

    test('uploadFoodPhoto omits meal_id when null', () async {
      final harness = _build(<String, dynamic>{
        'id': 'photo-1',
        'type': 'food_plate',
        'status': 'processing',
        'message': '',
      });

      await harness.client.uploadFoodPhoto(
        bytes: const [9, 9],
        filename: 'x.png',
      );

      final form = harness.interceptor.lastRequest!.data as FormData;
      final keys = form.fields.map((f) => f.key);
      expect(keys, isNot(contains('meal_id')));
    });

    test('fetchPhotoStatus parses complete status + foods from result.foods',
        () async {
      final harness = _build(<String, dynamic>{
        'id': 'photo-123',
        'type': 'food_plate',
        'status': 'complete',
        'result': {
          'foods': [
            {
              'name': 'Grilled salmon',
              'portion': 'approximately 1 fillet',
              'confidence': 0.82,
            },
            {'name': 'Side salad', 'portion': null, 'confidence': 0.4},
          ],
          'source': 'food_plate_vision',
        },
        'error': null,
      });

      final analysis = await harness.client.fetchPhotoStatus('photo-123');

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/photos/photo-123/status');
      expect(req.method, 'GET');

      expect(analysis.status, 'complete');
      expect(analysis.isComplete, isTrue);
      expect(analysis.foods, hasLength(2));
      expect(analysis.foods.first.name, 'Grilled salmon');
      expect(analysis.foods.first.portion, 'approximately 1 fillet');
      expect(analysis.foods.first.confidence, closeTo(0.82, 1e-9));
      expect(analysis.foods[1].portion, isNull);
    });

    test('fetchPhotoStatus parses failed status + error, empty foods',
        () async {
      final harness = _build(<String, dynamic>{
        'id': 'photo-9',
        'type': 'food_plate',
        'status': 'failed',
        'result': null,
        'error': 'Vision model unavailable',
      });

      final analysis = await harness.client.fetchPhotoStatus('photo-9');

      expect(analysis.isFailed, isTrue);
      expect(analysis.error, 'Vision model unavailable');
      expect(analysis.foods, isEmpty);
    });

    test('retryPhoto posts to /api/photos/{id}/retry', () async {
      final harness = _build(<String, dynamic>{
        'id': 'photo-9',
        'type': 'food_plate',
        'status': 'processing',
        'result': null,
        'error': null,
      });

      await harness.client.retryPhoto('photo-9');

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/photos/photo-9/retry');
      expect(req.method, 'POST');
    });
  });
}
