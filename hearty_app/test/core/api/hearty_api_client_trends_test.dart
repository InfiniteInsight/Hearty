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
  group('HeartyApiClient trends conversation', () {
    test('trendsConversation parses reply and a non-null proposed_verdict',
        () async {
      final harness = _build(<String, dynamic>{
        'reply': 'It sounds like dairy might be a trigger for you.',
        'proposed_verdict': {
          'category': 'dairy',
          'outcome_type': 'symptom',
          'outcome_name': 'bloating',
          'verdict': 'confirmed',
        },
        'is_closing': true,
      });

      final result = await harness.client.trendsConversation([
        {'role': 'user', 'content': 'Why do I keep bloating?'},
      ]);

      // Request shape.
      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/trends/conversation');
      expect(req.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      final history = body['history'] as List<dynamic>;
      expect(history, hasLength(1));
      expect((history.first as Map)['role'], 'user');
      expect((history.first as Map)['content'], 'Why do I keep bloating?');

      // Parsed result.
      expect(result.reply, 'It sounds like dairy might be a trigger for you.');
      expect(result.isClosing, isTrue);
      expect(result.proposedVerdict, isNotNull);
      expect(result.proposedVerdict!.category, 'dairy');
      expect(result.proposedVerdict!.outcomeType, 'symptom');
      expect(result.proposedVerdict!.outcomeName, 'bloating');
      expect(result.proposedVerdict!.verdict, 'confirmed');
    });

    test('trendsConversation maps a null proposed_verdict to null', () async {
      final harness = _build(<String, dynamic>{
        'reply': 'Tell me more about how you have been feeling.',
        'proposed_verdict': null,
        'is_closing': false,
      });

      final result = await harness.client.trendsConversation(const []);

      expect(result.reply, 'Tell me more about how you have been feeling.');
      expect(result.isClosing, isFalse);
      expect(result.proposedVerdict, isNull);
    });

    test('submitSignalVerdict posts the four snake_case fields', () async {
      final harness = _build(<String, dynamic>{'ok': true});

      await harness.client.submitSignalVerdict(
        category: 'dairy',
        outcomeType: 'symptom',
        outcomeName: 'bloating',
        verdict: 'confirmed',
      );

      final req = harness.interceptor.lastRequest!;
      expect(req.path, '/api/trends/signal-verdict');
      expect(req.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      expect(body['category'], 'dairy');
      expect(body['outcome_type'], 'symptom');
      expect(body['outcome_name'], 'bloating');
      expect(body['verdict'], 'confirmed');
    });
  });
}
