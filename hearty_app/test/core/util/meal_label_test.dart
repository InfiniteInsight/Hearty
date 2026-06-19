import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/util/meal_label.dart';

void main() {
  group('mealTimelineTitle', () {
    test('joins the extracted foods, capitalized, when present', () {
      expect(
        mealTimelineTitle(['turkey sandwich', 'potato chips'], 'I had a turkey sandwich and potato chips'),
        'Turkey sandwich, Potato chips',
      );
    });

    test('a single food is capitalized', () {
      expect(mealTimelineTitle(['oatmeal'], 'some oatmeal'), 'Oatmeal');
    });

    test('reflects an edit — a removed food no longer appears', () {
      // After the user removed "potato chips" from the meal's foods.
      expect(
        mealTimelineTitle(['turkey sandwich'], 'I had a turkey sandwich and potato chips'),
        'Turkey sandwich',
      );
    });

    test('falls back to the description when no foods were kept', () {
      expect(mealTimelineTitle([], 'I had something'), 'I had something');
    });

    test('blank/whitespace food entries are dropped; all-blank falls back', () {
      expect(mealTimelineTitle(['  ', 'rice'], 'desc'), 'Rice');
      expect(mealTimelineTitle(['  ', ''], 'just the description'), 'just the description');
    });
  });
}
