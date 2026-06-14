import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/trends_data.dart';

// The offline cache persists TrendsData.toJson() and rehydrates via
// fromSignalsJson(). These guard that the persistence fields + the resolved
// list survive that round-trip (otherwise badges/sparkline/resolved vanish on
// an offline reload).
void main() {
  test('FoodSignal persistence fields survive toJson -> fromSignalsJson', () {
    final original = TrendsData.fromSignalsJson({
      'signals': [
        {
          'category': 'dairy',
          'unified_score': 0.8,
          'channels': <dynamic>[],
          'convergent': false,
          'years_seen': [2024, 2025],
          'recurring': true,
          'is_new': false,
          'strength_by_year': {'2024': 0.7, '2025': 0.8},
        }
      ],
      'analyzed_at': null,
      'resolved': <dynamic>[],
    });

    final round = TrendsData.fromSignalsJson(original.toJson());
    final sig = round.signals.single;
    expect(sig.recurring, isTrue);
    expect(sig.yearsSeen, [2024, 2025]);
    expect(sig.strengthByYear['2025'], 0.8);
  });

  test('resolved list survives toJson -> fromSignalsJson', () {
    final original = TrendsData.fromSignalsJson({
      'signals': <dynamic>[],
      'analyzed_at': null,
      'resolved': [
        {'category': 'gluten', 'last_year': 2025, 'strength': 0.6,
         'status': 'potentially_resolved'},
        {'category': 'dairy', 'last_year': 2025, 'strength': 0.7,
         'status': 'resolved'},
      ],
    });

    final round = TrendsData.fromSignalsJson(original.toJson());
    expect(round.resolved.length, 2);
    final dairy = round.resolved.firstWhere((r) => r.category == 'dairy');
    expect(dairy.status, 'resolved');
    expect(dairy.lastYear, 2025);
  });
}
