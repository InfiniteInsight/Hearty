import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/trends_data.dart';

void main() {
  test('TrendsData parses the resolved array', () {
    final data = TrendsData.fromSignalsJson({
      'signals': <dynamic>[],
      'resolved': [
        {
          'category': 'dairy_casein',
          'category_label': 'Dairy / Casein',
          'last_year': 2024,
          'strength': 0.6,
          'status': 'resolved',
        },
        {
          // No category_label → fallback prettify.
          'category': 'high_sugar_refined',
          'last_year': 2023,
          'strength': 0.4,
          'status': 'potentially_resolved',
        },
      ],
    });

    expect(data.resolved.length, 2);
    expect(data.resolved.first.category, 'dairy_casein');
    // Backend label is kept; the raw slug stays available for keys/logic.
    expect(data.resolved.first.categoryLabel, 'Dairy / Casein');
    expect(data.resolved.first.lastYear, 2024);
    expect(data.resolved.first.status, 'resolved');
    expect(data.resolved.first.strength, 0.6);
    expect(data.resolved[1].status, 'potentially_resolved');
    // Missing category_label falls back to a prettified slug.
    expect(data.resolved[1].categoryLabel, 'High Sugar Refined');
  });

  test('TrendsData resolved defaults to empty when absent', () {
    final data = TrendsData.fromSignalsJson({
      'signals': <dynamic>[],
    });
    expect(data.resolved, isEmpty);
  });

  test('ResolvedSignal.fromJson defaults missing fields', () {
    final r = ResolvedSignal.fromJson(<String, dynamic>{});
    expect(r.category, '');
    expect(r.categoryLabel, '');
    expect(r.lastYear, 0);
    expect(r.strength, 0.0);
    expect(r.status, 'potentially_resolved');
  });
}
