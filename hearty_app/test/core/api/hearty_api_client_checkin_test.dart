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

void main() {
  group('HeartyApiClient check-in', () {
    test('fetchCheckinGaps parses expired flag and gap list', () async {
      final harness = _build(<String, dynamic>{
        'target_date': '2026-06-11',
        'expired': true,
        'gaps': [
          {
            'type': 'symptom_gap',
            'prompt': 'How did the turkey sandwich sit with you?',
            'meal_id': 'meal-123',
          },
          {
            'type': 'low_confidence',
            'prompt': 'Was that a banana or a plantain?',
            'meal_id': 'meal-456',
            'food_name': 'banana',
          },
        ],
      });

      final result = await harness.client.fetchCheckinGaps(
        DateTime(2026, 6, 11),
      );

      // Request shape.
      expect(harness.interceptor.lastRequest!.path, '/api/checkin/gaps');
      expect(
        harness.interceptor.lastRequest!.queryParameters['date'],
        '2026-06-11',
      );

      // Parsed result.
      expect(result.targetDate, '2026-06-11');
      expect(result.expired, isTrue);
      expect(result.gaps, hasLength(2));
      expect(result.gaps[0].type, 'symptom_gap');
      expect(result.gaps[0].prompt, 'How did the turkey sandwich sit with you?');
      expect(result.gaps[0].mealId, 'meal-123');
      expect(result.gaps[1].type, 'low_confidence');
      expect(result.gaps[1].foodName, 'banana');
    });

    test('resolveSymptomGap posts the expected path and body, omitting nulls',
        () async {
      final harness = _build(<String, dynamic>{'ok': true});

      await harness.client.resolveSymptomGap(
        mealId: 'meal-123',
        rawDescription: 'mild bloating',
        severity: 3,
      );

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/checkin/resolve/symptom');
      expect(req.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      expect(body['meal_id'], 'meal-123');
      expect(body['raw_description'], 'mild bloating');
      expect(body['severity'], 3);
      // Null optionals must be omitted, not sent as null.
      expect(body.containsKey('symptom_type'), isFalse);
      expect(body.containsKey('onset_minutes'), isFalse);
    });

    test('skipSymptomGap posts meal_id to the skip endpoint', () async {
      final harness = _build(<String, dynamic>{'ok': true});

      await harness.client.skipSymptomGap(mealId: 'meal-789');

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/checkin/skip/symptom');
      expect(req.method, 'POST');
      expect((req.data as Map<String, dynamic>)['meal_id'], 'meal-789');
    });

    test('dismissSymptomFollowUp posts meal_id to the dismiss endpoint',
        () async {
      final harness = _build(<String, dynamic>{'ok': true});

      await harness.client.dismissSymptomFollowUp(mealId: 'meal-789');

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/checkin/dismiss/symptom');
      expect(req.method, 'POST');
      expect((req.data as Map<String, dynamic>)['meal_id'], 'meal-789');
    });

    test('resolveFoodGap posts only the provided fields', () async {
      final harness = _build(<String, dynamic>{'ok': true});

      await harness.client.resolveFoodGap(
        mealId: 'meal-1',
        confirmed: true,
      );

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/checkin/resolve/food');
      final body = req.data as Map<String, dynamic>;
      expect(body['meal_id'], 'meal-1');
      expect(body['confirmed'], isTrue);
      expect(body.containsKey('food_name'), isFalse);
      expect(body.containsKey('corrected_description'), isFalse);
    });

    test('resolveMealGap posts description and ISO8601 logged_at', () async {
      final harness = _build(<String, dynamic>{'ok': true});

      final loggedAt = DateTime.utc(2026, 6, 11, 12, 30);
      await harness.client.resolveMealGap(
        description: 'a bowl of oatmeal',
        loggedAt: loggedAt,
      );

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/checkin/resolve/meal');
      final body = req.data as Map<String, dynamic>;
      expect(body['description'], 'a bowl of oatmeal');
      expect(body['logged_at'], loggedAt.toUtc().toIso8601String());
    });
  });
}
