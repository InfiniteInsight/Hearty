import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/checkin_gap.dart';
import 'package:hearty_app/features/checkin/providers/checkin_controller.dart';

/// Records every call to the five check-in methods the controller uses and
/// returns a canned [CheckinGapsResult]. Implements [HeartyApiClient] but only
/// overrides what the controller touches; [noSuchMethod] makes any other call
/// fail loudly (it would mean the controller did something unexpected).
class FakeHeartyApiClient implements HeartyApiClient {
  FakeHeartyApiClient({
    CheckinGapsResult? gapsResult,
    this.throwOnFetch = false,
  }) : _gapsResult = gapsResult;

  CheckinGapsResult? _gapsResult;
  bool throwOnFetch;

  // Recorded calls.
  final List<DateTime> fetchedDates = [];
  final List<Map<String, dynamic>> resolveSymptomCalls = [];
  final List<String> skipSymptomMealIds = [];
  final List<Map<String, dynamic>> resolveFoodCalls = [];
  final List<Map<String, dynamic>> resolveMealCalls = [];

  void setGaps(CheckinGapsResult result) => _gapsResult = result;

  @override
  Future<CheckinGapsResult> fetchCheckinGaps(DateTime date) async {
    fetchedDates.add(date);
    if (throwOnFetch) throw Exception('boom');
    return _gapsResult!;
  }

  @override
  Future<void> resolveSymptomGap({
    required String mealId,
    required String rawDescription,
    String? symptomType,
    int? severity,
    int? onsetMinutes,
    DateTime? loggedAt,
  }) async {
    resolveSymptomCalls.add({
      'mealId': mealId,
      'rawDescription': rawDescription,
      'severity': severity,
      'loggedAt': loggedAt,
    });
  }

  @override
  Future<void> skipSymptomGap({required String mealId}) async {
    skipSymptomMealIds.add(mealId);
  }

  @override
  Future<void> resolveFoodGap({
    required String mealId,
    String? foodName,
    bool? confirmed,
    String? correctedDescription,
  }) async {
    resolveFoodCalls.add({
      'mealId': mealId,
      'foodName': foodName,
      'confirmed': confirmed,
      'correctedDescription': correctedDescription,
    });
  }

  @override
  Future<void> resolveMealGap({
    required String description,
    required DateTime loggedAt,
  }) async {
    resolveMealCalls.add({'description': description, 'loggedAt': loggedAt});
  }

  // Any other client method being hit is a test failure, not a silent no-op.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CheckinGap _symptom(String mealId) =>
    CheckinGap(type: 'symptom_gap', prompt: 'how did you feel?', mealId: mealId);

CheckinGap _lowConfidence(String mealId, String foodName) => CheckinGap(
      type: 'low_confidence',
      prompt: 'was it $foodName?',
      mealId: mealId,
      foodName: foodName,
    );

CheckinGap _missingChunk({String? windowStart}) => CheckinGap(
      type: 'missing_chunk',
      prompt: 'anything around then?',
      windowStart: windowStart,
    );

CheckinGapsResult _result({
  required List<CheckinGap> gaps,
  bool expired = false,
  String targetDate = '2026-06-13',
}) =>
    CheckinGapsResult(targetDate: targetDate, expired: expired, gaps: gaps);

void main() {
  final date = DateTime(2026, 6, 13);

  group('load()', () {
    test('populates gaps and enters preview (non-expired)', () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(gaps: [_symptom('m1'), _lowConfidence('m2', 'rice')]),
      );
      final c = CheckinController(api, date: date);

      await c.load();

      expect(c.state.phase, CheckinPhase.preview);
      expect(c.state.gaps.length, 2);
      expect(c.state.expired, isFalse);
      expect(c.state.targetDate, '2026-06-13');
      expect(api.fetchedDates.single, date);
    });

    test('expired result → done + expired, no gaps', () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(gaps: [_symptom('m1')], expired: true),
      );
      final c = CheckinController(api, date: date);

      await c.load();

      expect(c.state.phase, CheckinPhase.done);
      expect(c.state.expired, isTrue);
      expect(c.state.gaps, isEmpty);
    });

    test('empty gaps (non-expired) → done, not expired', () async {
      final api = FakeHeartyApiClient(gapsResult: _result(gaps: []));
      final c = CheckinController(api, date: date);

      await c.load();

      expect(c.state.phase, CheckinPhase.done);
      expect(c.state.expired, isFalse);
    });

    test('fetch throws → error phase', () async {
      final api = FakeHeartyApiClient(throwOnFetch: true);
      final c = CheckinController(api, date: date);

      await c.load();

      expect(c.state.phase, CheckinPhase.error);
    });
  });

  group('preview → begin', () {
    test('toggleSkip then begin starts at first non-skipped gap', () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(gaps: [
          _symptom('m1'),
          _lowConfidence('m2', 'rice'),
          _missingChunk(),
        ]),
      );
      final c = CheckinController(api, date: date);
      await c.load();

      c.toggleSkip(0); // skip the first gap
      c.begin();

      expect(c.state.phase, CheckinPhase.cycling);
      expect(c.state.index, 1);
      expect(c.state.current!.mealId, 'm2');
    });

    test('skipAll then begin → done', () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(gaps: [_symptom('m1'), _missingChunk()]),
      );
      final c = CheckinController(api, date: date);
      await c.load();

      c.skipAll();
      c.begin();

      expect(c.state.phase, CheckinPhase.done);
      expect(c.state.current, isNull);
    });

    test('toggleSkip is idempotent toggle (skip then unskip)', () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(gaps: [_symptom('m1'), _missingChunk()]),
      );
      final c = CheckinController(api, date: date);
      await c.load();

      c.toggleSkip(0);
      c.toggleSkip(0); // back on
      c.begin();

      expect(c.state.index, 0);
    });
  });

  group('resolve dispatch + advance', () {
    test('resolveSymptom passes mealId + target-day loggedAt, then advances',
        () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(gaps: [_symptom('m1'), _lowConfidence('m2', 'rice')]),
      );
      final c = CheckinController(api, date: date);
      await c.load();
      c.begin();

      await c.resolveSymptom(rawDescription: 'bloated', severity: 3);

      final call = api.resolveSymptomCalls.single;
      expect(call['mealId'], 'm1');
      expect(call['rawDescription'], 'bloated');
      expect(call['severity'], 3);
      final loggedAt = call['loggedAt'] as DateTime;
      expect(loggedAt.year, 2026);
      expect(loggedAt.month, 6);
      expect(loggedAt.day, 13);

      // Advanced to the next gap.
      expect(c.state.index, 1);
      expect(c.state.current!.mealId, 'm2');
    });

    test('confirmFood resolves the food gap with confirmed: true', () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(gaps: [_lowConfidence('m2', 'rice')]),
      );
      final c = CheckinController(api, date: date);
      await c.load();
      c.begin();

      await c.confirmFood();

      final call = api.resolveFoodCalls.single;
      expect(call['mealId'], 'm2');
      expect(call['foodName'], 'rice');
      expect(call['confirmed'], isTrue);
      expect(c.state.phase, CheckinPhase.done); // past the last gap
    });

    test('logMeal uses windowStart when present', () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(
          gaps: [_missingChunk(windowStart: '2026-06-13T15:30:00')],
        ),
      );
      final c = CheckinController(api, date: date);
      await c.load();
      c.begin();

      await c.logMeal('a sandwich');

      final call = api.resolveMealCalls.single;
      expect(call['description'], 'a sandwich');
      expect(call['loggedAt'], DateTime.parse('2026-06-13T15:30:00'));
    });
  });

  group('skipCurrent', () {
    test('symptom_gap calls skipSymptomGap and advances', () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(gaps: [_symptom('m1'), _missingChunk()]),
      );
      final c = CheckinController(api, date: date);
      await c.load();
      c.begin();

      await c.skipCurrent();

      expect(api.skipSymptomMealIds.single, 'm1');
      expect(c.state.index, 1);
      expect(c.state.current!.type, 'missing_chunk');
    });

    test('low_confidence makes no resolve call and just advances', () async {
      final api = FakeHeartyApiClient(
        gapsResult: _result(gaps: [_lowConfidence('m2', 'rice'), _missingChunk()]),
      );
      final c = CheckinController(api, date: date);
      await c.load();
      c.begin();

      await c.skipCurrent();

      expect(api.resolveFoodCalls, isEmpty);
      expect(api.skipSymptomMealIds, isEmpty);
      expect(c.state.index, 1);
    });
  });

  test('advancing past the last gap → done', () async {
    final api = FakeHeartyApiClient(
      gapsResult: _result(gaps: [_symptom('m1')]),
    );
    final c = CheckinController(api, date: date);
    await c.load();
    c.begin();

    await c.skipCurrent();

    expect(c.state.phase, CheckinPhase.done);
    expect(c.state.current, isNull);
  });
}
