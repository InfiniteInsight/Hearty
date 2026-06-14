import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/trends_data.dart';
import 'package:hearty_app/features/trends/screens/trends_screen.dart';

void main() {
  Widget host(List<ResolvedSignal> resolved) =>
      MaterialApp(home: Scaffold(body: ResolvedSection(resolved: resolved)));

  testWidgets('renders firm + potential rows with labels', (t) async {
    await t.pumpWidget(host(const [
      ResolvedSignal(
          category: 'dairy_casein',
          lastYear: 2024,
          strength: 0.6,
          status: 'resolved'),
      ResolvedSignal(
          category: 'gluten',
          lastYear: 2023,
          strength: 0.4,
          status: 'potentially_resolved'),
    ]));

    expect(find.byKey(const Key('trends-resolved-section')), findsOneWidget);
    expect(find.text('No longer flagging'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Possibly resolved'), findsOneWidget);
  });

  testWidgets('handles multiple same-status items without key collision',
      (t) async {
    await t.pumpWidget(host(const [
      ResolvedSignal(
          category: 'dairy_casein',
          lastYear: 2024,
          strength: 0.6,
          status: 'resolved'),
      ResolvedSignal(
          category: 'gluten',
          lastYear: 2024,
          strength: 0.5,
          status: 'resolved'),
      ResolvedSignal(
          category: 'soy',
          lastYear: 2023,
          strength: 0.4,
          status: 'potentially_resolved'),
      ResolvedSignal(
          category: 'eggs',
          lastYear: 2023,
          strength: 0.3,
          status: 'potentially_resolved'),
    ]));

    expect(find.byKey(const Key('trends-resolved-section')), findsOneWidget);
    expect(find.text('Resolved'), findsNWidgets(2));
    expect(find.text('Possibly resolved'), findsNWidgets(2));
  });

  testWidgets('empty list collapses to nothing', (t) async {
    await t.pumpWidget(host(const []));
    expect(find.byKey(const Key('trends-resolved-section')), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget);
  });
}
