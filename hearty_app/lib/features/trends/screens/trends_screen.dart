import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/models/trends_data.dart';
import '../../../core/api/providers/trends_provider.dart';

// ---------------------------------------------------------------------------
// Color palette for symptom lines
// ---------------------------------------------------------------------------

const _kSymptomColors = [
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.red,
  Colors.indigo,
  Colors.green,
  Colors.brown,
  Colors.cyan,
];

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  int _selectedDays = 30;

  static const _chips = [
    (label: '7 days', days: 7),
    (label: '30 days', days: 30),
    (label: '90 days', days: 90),
    (label: 'All time', days: 365),
  ];

  void _selectDays(int days) {
    setState(() => _selectedDays = days);
    ref.read(trendsProvider.notifier).setDays(days);
  }

  @override
  Widget build(BuildContext context) {
    final asyncTrends = ref.watch(trendsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date-range chips
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: _chips.map((chip) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(chip.label),
                    selected: _selectedDays == chip.days,
                    onSelected: (_) => _selectDays(chip.days),
                  ),
                );
              }).toList(),
            ),
          ),

          // Charts area
          Expanded(
            child: asyncTrends.when(
              loading: () => const _LoadingSkeleton(),
              error: (err, _) => Center(
                child: GestureDetector(
                  onTap: () => ref.invalidate(trendsProvider),
                  child: const Text(
                    'Failed to load trends — tap to retry',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
              data: (trends) => _TrendsBody(trends: trends),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: List.generate(4, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 16,
                    width: 140,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 200,
                      child: Column(
                        children: [
                          const LinearProgressIndicator(),
                          Expanded(
                            child: Container(color: Colors.grey.shade200),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// All four charts
// ---------------------------------------------------------------------------

class _TrendsBody extends StatelessWidget {
  const _TrendsBody({required this.trends});

  final TrendsData trends;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SymptomFrequencyChart(data: trends.symptomFrequency),
        const SizedBox(height: 16),
        _TriggerFoodsChart(data: trends.topTriggerFoods),
        const SizedBox(height: 16),
        _EnergyMoodChart(data: trends.wellbeingTrend),
        const SizedBox(height: 16),
        _MealTypeChart(data: trends.mealTypeDistribution),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chart 1 — Symptom Frequency (LineChart)
// ---------------------------------------------------------------------------

class _SymptomFrequencyChart extends StatelessWidget {
  const _SymptomFrequencyChart({required this.data});

  final List<SymptomFrequencyPoint> data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Symptom Frequency',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: data.isEmpty
                  ? const Center(child: Text('No symptom data'))
                  : _buildChart(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    // Find earliest date for x-offset calculation.
    final dates = data.map((p) => p.date).toList()..sort();
    final earliest = dates.first;

    // Group by symptomType.
    final grouped = <String, List<SymptomFrequencyPoint>>{};
    for (final p in data) {
      grouped.putIfAbsent(p.symptomType, () => []).add(p);
    }

    final sortedTypes = grouped.keys.toList()..sort();

    double maxY = 1;
    for (final p in data) {
      if (p.count > maxY) maxY = p.count.toDouble();
    }

    final lines = sortedTypes.asMap().entries.map((entry) {
      final idx = entry.key;
      final type = entry.value;
      final color = _kSymptomColors[idx % _kSymptomColors.length];
      final points = grouped[type]!
          .map((p) => FlSpot(
                p.date.difference(earliest).inDays.toDouble(),
                p.count.toDouble(),
              ))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));

      return LineChartBarData(
        spots: points,
        isCurved: true,
        color: color,
        barWidth: 2,
        dotData: const FlDotData(show: true),
      );
    }).toList();

    return LineChart(
      LineChartData(
        lineBarsData: lines,
        minY: 0,
        maxY: maxY + 1,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                if (value != value.floorToDouble()) return const SizedBox();
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final date = earliest.add(Duration(days: value.toInt()));
                return Text(
                  '${date.month}/${date.day}',
                  style: const TextStyle(fontSize: 9),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart 2 — Top Trigger Foods (BarChart — vertical with rotated labels)
// ---------------------------------------------------------------------------

class _TriggerFoodsChart extends StatelessWidget {
  const _TriggerFoodsChart({required this.data});

  final List<TriggerFood> data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Trigger Foods',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: data.isEmpty
                  ? const Center(child: Text('No trigger food data'))
                  : _buildChart(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final top5 = data.take(5).toList();

    final barGroups = top5.asMap().entries.map((entry) {
      final idx = entry.key;
      final food = entry.value;
      return BarChartGroupData(
        x: idx,
        barRods: [
          BarChartRodData(
            toY: food.confidenceScore,
            color: Colors.deepOrange,
            width: 24,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        barGroups: barGroups,
        minY: 0,
        maxY: 1.0,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= top5.length) return const SizedBox();
                final label = top5[idx].food;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Transform.rotate(
                    angle: -math.pi / 4,
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 9),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart 3 — Energy & Mood (dual LineChart)
// ---------------------------------------------------------------------------

class _EnergyMoodChart extends StatelessWidget {
  const _EnergyMoodChart({required this.data});

  final List<WellbeingPoint> data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Energy & Mood',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: data.isEmpty
                  ? const Center(child: Text('No wellbeing data'))
                  : _buildChart(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final sorted = [...data]..sort((a, b) => a.date.compareTo(b.date));
    final earliest = sorted.first.date;

    FlSpot toSpot(DateTime date, double value) => FlSpot(
          date.difference(earliest).inDays.toDouble(),
          value,
        );

    final energyLine = LineChartBarData(
      spots: sorted.map((p) => toSpot(p.date, p.energy)).toList(),
      isCurved: true,
      color: Colors.blue,
      barWidth: 2,
      dotData: const FlDotData(show: true),
    );

    final moodLine = LineChartBarData(
      spots: sorted.map((p) => toSpot(p.date, p.mood)).toList(),
      isCurved: true,
      color: Colors.pinkAccent,
      barWidth: 2,
      dotData: const FlDotData(show: true),
    );

    return Column(
      children: [
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: Colors.blue, label: 'Energy'),
            const SizedBox(width: 16),
            _LegendDot(color: Colors.pinkAccent, label: 'Mood'),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LineChart(
            LineChartData(
              lineBarsData: [energyLine, moodLine],
              minY: 1,
              maxY: 5,
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      if (value != value.floorToDouble()) {
                        return const SizedBox();
                      }
                      return Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final date =
                          earliest.add(Duration(days: value.toInt()));
                      return Text(
                        '${date.month}/${date.day}',
                        style: const TextStyle(fontSize: 9),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: true),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chart 4 — Meal Type Distribution (PieChart)
// ---------------------------------------------------------------------------

class _MealTypeChart extends StatelessWidget {
  const _MealTypeChart({required this.data});

  final Map<String, int> data;

  // Distinct colors for pie slices.
  static const _kPieColors = [
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.red,
    Colors.purple,
    Colors.teal,
    Colors.amber,
    Colors.indigo,
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Meal Types',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: data.isEmpty
                  ? const Center(child: Text('No meal data'))
                  : _buildChart(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final entries = data.entries.toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    final sections = entries.asMap().entries.map((entry) {
      final idx = entry.key;
      final mapEntry = entry.value;
      final color = _kPieColors[idx % _kPieColors.length];
      final pct = total > 0 ? (mapEntry.value / total * 100) : 0;
      return PieChartSectionData(
        value: mapEntry.value.toDouble(),
        color: color,
        title: '${pct.toStringAsFixed(0)}%',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 30,
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: entries.asMap().entries.map((entry) {
            final idx = entry.key;
            final mapEntry = entry.value;
            final color = _kPieColors[idx % _kPieColors.length];
            return _LegendDot(
              color: color,
              label: '${mapEntry.key} (${mapEntry.value})',
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared legend helper
// ---------------------------------------------------------------------------

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
