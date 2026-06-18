import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/experiment.dart';

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
  group('HeartyApiClient experiments', () {
    test('createExperiment posts the body and parses the response', () async {
      final harness = _build(<String, dynamic>{
        'id': 'exp-1',
        'category': 'dairy',
        'direction': 'reduce',
        'outcome_type': 'symptom',
        'outcome_name': 'bloating',
        'experiment_start': '2026-06-11',
        'experiment_end': '2026-06-25',
        'status': 'active',
        'result': null,
        'nudged_at': null,
        'adherence': null,
        'logged_days': null,
        'nudge_suggested': false,
      });

      final result = await harness.client.createExperiment(
        category: 'dairy',
        outcomeType: 'symptom',
        outcomeName: 'bloating',
      );

      // Request shape.
      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/experiments');
      expect(req.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      expect(body['category'], 'dairy');
      expect(body['outcome_type'], 'symptom');
      expect(body['outcome_name'], 'bloating');

      // Parsed result.
      expect(result.id, 'exp-1');
      expect(result.category, 'dairy');
      expect(result.direction, 'reduce');
      expect(result.outcomeType, 'symptom');
      expect(result.outcomeName, 'bloating');
      expect(result.experimentStart, '2026-06-11');
      expect(result.experimentEnd, '2026-06-25');
      expect(result.status, 'active');
      expect(result.result, isNull);
      expect(result.nudgeSuggested, isFalse);
    });

    test('fetchActiveExperiments parses adherence and nudgeSuggested', () async {
      final harness = _build(<String, dynamic>{
        'experiments': [
          {
            'id': 'exp-1',
            'category': 'dairy',
            'direction': 'reduce',
            'outcome_type': 'symptom',
            'outcome_name': 'bloating',
            'experiment_start': '2026-06-11',
            'experiment_end': '2026-06-25',
            'status': 'active',
            'result': null,
            'nudged_at': null,
            'adherence': 0.75,
            'logged_days': 9,
            'nudge_suggested': true,
          },
        ],
      });

      final result = await harness.client.fetchActiveExperiments();

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/experiments/active');
      expect(req.method, 'GET');

      expect(result, hasLength(1));
      expect(result.first.id, 'exp-1');
      expect(result.first.adherence, 0.75);
      expect(result.first.loggedDays, 9);
      expect(result.first.nudgeSuggested, isTrue);
    });

    test('evaluateExperiment parses a populated result map', () async {
      final harness = _build(<String, dynamic>{
        'id': 'exp-1',
        'category': 'dairy',
        'direction': 'reduce',
        'outcome_type': 'symptom',
        'outcome_name': 'bloating',
        'experiment_start': '2026-06-11',
        'experiment_end': '2026-06-25',
        'status': 'complete',
        'result': {
          'verdict': 'improved',
          'reason': 'Bloating dropped notably during the test window.',
          'adherence': 0.9,
          'baseline_rate': 0.5,
          'experiment_rate': 0.1,
          'logged_days': 13,
        },
        'nudged_at': null,
        'adherence': 0.9,
        'logged_days': 13,
        'nudge_suggested': false,
      });

      final result = await harness.client.evaluateExperiment('exp-1');

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/experiments/exp-1/evaluate');
      expect(req.method, 'POST');

      expect(result.status, 'complete');
      expect(result.result, isNotNull);
      expect(result.result!['verdict'], 'improved');
      expect(result.result!['baseline_rate'], 0.5);
    });

    test('abandonExperiment issues a POST to the right path', () async {
      final harness = _build(<String, dynamic>{'ok': true});

      await harness.client.abandonExperiment('exp-1');

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/experiments/exp-1/abandon');
      expect(req.method, 'POST');
    });

    test('restartExperiment parses the fresh experiment', () async {
      final harness = _build(<String, dynamic>{
        'id': 'exp-2',
        'category': 'dairy',
        'direction': 'reduce',
        'outcome_type': 'symptom',
        'outcome_name': 'bloating',
        'experiment_start': '2026-06-15',
        'experiment_end': '2026-06-29',
        'status': 'active',
        'result': null,
        'nudge_suggested': false,
      });

      final result = await harness.client.restartExperiment('exp-1');

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/experiments/exp-1/restart');
      expect(req.method, 'POST');
      expect(result.id, 'exp-2');
      expect(result.status, 'active');
    });

    test('ackExperimentNudge issues a POST to the ack-nudge path', () async {
      final harness = _build(<String, dynamic>{'ok': true});

      await harness.client.ackExperimentNudge('exp-1');

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/experiments/exp-1/ack-nudge');
      expect(req.method, 'POST');
    });
  });

  group('ProposedExperiment', () {
    test('fromJson parses the three snake_case fields', () {
      final parsed = ProposedExperiment.fromJson(const {
        'category': 'dairy',
        'outcome_type': 'symptom',
        'outcome_name': 'bloating',
      });

      expect(parsed.category, 'dairy');
      expect(parsed.outcomeType, 'symptom');
      expect(parsed.outcomeName, 'bloating');
    });

    test('fromJson defaults missing fields to empty strings', () {
      final parsed = ProposedExperiment.fromJson(const {});

      expect(parsed.category, '');
      expect(parsed.outcomeType, '');
      expect(parsed.outcomeName, '');
    });
  });
}
