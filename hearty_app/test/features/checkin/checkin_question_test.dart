import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/checkin_gap.dart';
import 'package:hearty_app/features/checkin/checkin_question.dart';

void main() {
  // DateTimes are constructed in LOCAL time (DateTime(...) is local), so
  // toLocal() is a no-op and the formatted clock is machine-tz-independent.
  group('symptom_gap', () {
    test('names the meal with type and local time', () {
      final gap = CheckinGap(
        type: 'symptom_gap',
        prompt: 'How did your stomach feel after that meal?',
        mealId: 'm1',
        mealLabel: 'grilled chicken salad',
        mealType: 'lunch',
        mealTime: DateTime(2026, 6, 3, 12, 30),
      );
      expect(
        checkinQuestionText(gap),
        'How did your stomach feel after your grilled chicken salad — '
        'lunch, around 12:30 PM?',
      );
    });

    test('drops the type segment when meal_type is absent', () {
      final gap = CheckinGap(
        type: 'symptom_gap',
        prompt: 'How did your stomach feel after that meal?',
        mealLabel: 'toast',
        mealTime: DateTime(2026, 6, 3, 8, 5),
      );
      expect(
        checkinQuestionText(gap),
        'How did your stomach feel after your toast, around 8:05 AM?',
      );
    });

    test('falls back to prompt when meal_label is null', () {
      final gap = CheckinGap(
        type: 'symptom_gap',
        prompt: 'How did your stomach feel after that meal?',
        mealTime: DateTime(2026, 6, 3, 12, 30),
      );
      expect(checkinQuestionText(gap),
          'How did your stomach feel after that meal?');
    });
  });

  group('low_confidence', () {
    test('names the meal it belongs to', () {
      final gap = CheckinGap(
        type: 'low_confidence',
        prompt: 'I logged "buldak ramen" but wasn\'t sure I got it right — did I?',
        foodName: 'buldak ramen',
        mealType: 'dinner',
        mealTime: DateTime(2026, 6, 3, 19, 0),
      );
      expect(
        checkinQuestionText(gap),
        'On your dinner around 7:00 PM, I logged "buldak ramen" — '
        'did I get that right?',
      );
    });

    test('uses "meal" when type is absent', () {
      final gap = CheckinGap(
        type: 'low_confidence',
        prompt: 'fallback',
        foodName: 'mystery dish',
        mealTime: DateTime(2026, 6, 3, 13, 15),
      );
      expect(
        checkinQuestionText(gap),
        'On your meal around 1:15 PM, I logged "mystery dish" — '
        'did I get that right?',
      );
    });

    test('falls back to prompt when meal_time is null', () {
      final gap = CheckinGap(
        type: 'low_confidence',
        prompt: 'I logged "x" but wasn\'t sure I got it right — did I?',
        foodName: 'x',
      );
      expect(checkinQuestionText(gap),
          'I logged "x" but wasn\'t sure I got it right — did I?');
    });
  });

  group('missing_chunk', () {
    test('names the real local time window', () {
      final gap = CheckinGap(
        type: 'missing_chunk',
        prompt: "I don't see anything logged for a stretch there — "
            'did you eat in that window?',
        windowStart: '2026-06-03T13:00:00',
        windowEnd: '2026-06-03T18:30:00',
      );
      expect(
        checkinQuestionText(gap),
        "I don't see anything logged between about 1:00 PM and 6:30 PM — "
        'did you eat then?',
      );
    });

    test('falls back to prompt when a window bound is missing', () {
      final gap = CheckinGap(
        type: 'missing_chunk',
        prompt: 'stretch fallback',
        windowStart: '2026-06-03T13:00:00',
      );
      expect(checkinQuestionText(gap), 'stretch fallback');
    });
  });

  test('unknown type returns prompt verbatim', () {
    final gap = CheckinGap(type: 'something_new', prompt: 'do the thing');
    expect(checkinQuestionText(gap), 'do the thing');
  });
}
