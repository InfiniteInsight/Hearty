import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/trends_data.dart';

void main() {
  test('FoodSignal parses persistence fields', () {
    final s = FoodSignal.fromJson({
      'category': 'dairy', 'unified_score': 0.8,
      'channels': <dynamic>[], 'convergent': false,
      'years_seen': [2024, 2025], 'recurring': true, 'is_new': false,
      'strength_by_year': {'2024': 0.7, '2025': 0.8},
    });
    expect(s.yearsSeen, [2024, 2025]);
    expect(s.recurring, isTrue);
    expect(s.isNew, isFalse);
    expect(s.strengthByYear['2025'], 0.8);
  });

  test('FoodSignal persistence fields default when absent', () {
    final s = FoodSignal.fromJson({
      'category': 'soy', 'unified_score': 0.4,
      'channels': <dynamic>[], 'convergent': false,
    });
    expect(s.yearsSeen, isEmpty);
    expect(s.recurring, isFalse);
    expect(s.isNew, isFalse);
    expect(s.strengthByYear, isEmpty);
  });
}
