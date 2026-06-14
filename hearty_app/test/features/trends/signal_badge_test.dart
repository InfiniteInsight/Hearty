import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/trends_data.dart';
import 'package:hearty_app/features/trends/screens/trends_screen.dart';

FoodSignal _sig({
  List<int> years = const [],
  bool recurring = false,
  bool isNew = false,
  Map<String, double> strengthByYear = const {},
}) =>
    FoodSignal.fromJson({
      'category': 'dairy', 'unified_score': 0.8,
      'channels': <dynamic>[], 'convergent': false,
      'years_seen': years, 'recurring': recurring, 'is_new': isNew,
      'strength_by_year': strengthByYear,
    });

void main() {
  Widget host(FoodSignal s) => MaterialApp(home: Scaffold(body: SignalCard(signal: s)));

  testWidgets('recurring shows a "Seen N years" badge', (t) async {
    await t.pumpWidget(host(_sig(years: [2024, 2025, 2026], recurring: true)));
    expect(find.byKey(const Key('signal-recurring-badge')), findsOneWidget);
    expect(find.textContaining('3 year'), findsOneWidget);
  });

  testWidgets('new this year shows a New chip', (t) async {
    await t.pumpWidget(host(_sig(years: [2026], isNew: true)));
    expect(find.byKey(const Key('signal-new-chip')), findsOneWidget);
  });

  testWidgets('single non-recurring year shows no badge', (t) async {
    await t.pumpWidget(host(_sig(years: [2025])));
    expect(find.byKey(const Key('signal-recurring-badge')), findsNothing);
    expect(find.byKey(const Key('signal-new-chip')), findsNothing);
  });

  testWidgets('recurring with multi-year strength shows a sparkline', (t) async {
    await t.pumpWidget(host(_sig(
      years: [2024, 2025],
      recurring: true,
      strengthByYear: {'2024': 0.5, '2025': 0.9},
    )));
    expect(find.byKey(const Key('signal-sparkline')), findsOneWidget);
  });

  testWidgets('single-year recurring strength shows no sparkline', (t) async {
    await t.pumpWidget(host(_sig(
      years: [2025],
      recurring: true,
      strengthByYear: {'2025': 0.9},
    )));
    expect(find.byKey(const Key('signal-sparkline')), findsNothing);
  });

  testWidgets('non-recurring with multi-year strength shows no sparkline', (t) async {
    await t.pumpWidget(host(_sig(
      strengthByYear: {'2024': 0.5, '2025': 0.9},
    )));
    expect(find.byKey(const Key('signal-sparkline')), findsNothing);
  });
}
