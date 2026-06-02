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
// Display helpers
// ---------------------------------------------------------------------------

String _formatCategory(String slug) {
  const labels = {
    'fodmap_fructans': 'FODMAP Fructans',
    'fodmap_fructose': 'FODMAP Fructose',
    'fodmap_polyols': 'FODMAP Polyols',
    'fodmap_gos': 'FODMAP GOS',
    'fodmap_lactose': 'FODMAP Lactose',
    'dairy_casein': 'Dairy / Casein',
    'gluten': 'Gluten',
    'eggs': 'Eggs',
    'soy': 'Soy',
    'histamine': 'High Histamine',
    'sulfites': 'Sulfites',
    'caffeine': 'Caffeine',
    'alcohol': 'Alcohol',
    'high_fat': 'High Fat',
    'cruciferous': 'Cruciferous',
    'nightshades': 'Nightshades',
    'high_sugar_refined': 'High Sugar',
    'spicy': 'Spicy',
  };
  return labels[slug] ?? slug.replaceAll('_', ' ').toUpperCase();
}

String _formatOutcomeName(String name) =>
    name.replaceAll('_', ' ').replaceFirstMapped(
      RegExp(r'^\w'),
      (m) => m[0]!.toUpperCase(),
    );

String _windowLabel(int? minutes) {
  if (minutes == null) return '';
  if (minutes < 60) return '${minutes}min';
  final h = minutes ~/ 60;
  return '${h}h window';
}

String _timeAgo(DateTime? dt) {
  if (dt == null) return 'Never analyzed';
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}min ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  bool _analysisLoading = false;

  Future<void> _runAnalysis() async {
    setState(() => _analysisLoading = true);
    try {
      await ref.read(trendsProvider.notifier).triggerAnalysis();
    } finally {
      if (mounted) setState(() => _analysisLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncTrends = ref.watch(trendsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trends'),
        actions: [
          if (_analysisLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Analyse now',
              onPressed: _runAnalysis,
            ),
        ],
      ),
      body: asyncTrends.when(
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
        data: (trends) => _TrendsBody(
          trends: trends,
          onAnalyse: _runAnalysis,
          analysisLoading: _analysisLoading,
        ),
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
                      height: 80,
                      child: Column(
                        children: [
                          const LinearProgressIndicator(),
                          Expanded(child: Container(color: Colors.grey.shade200)),
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
// Body — ranked signals + chart sections
// ---------------------------------------------------------------------------

class _TrendsBody extends StatelessWidget {
  const _TrendsBody({
    required this.trends,
    required this.onAnalyse,
    required this.analysisLoading,
  });

  final TrendsData trends;
  final VoidCallback onAnalyse;
  final bool analysisLoading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SignalsSection(
          signals: trends.signals,
          analyzedAt: trends.analyzedAt,
          onAnalyse: onAnalyse,
          analysisLoading: analysisLoading,
        ),
        const SizedBox(height: 16),
        if (trends.symptomFrequency.isNotEmpty) ...[
          _SymptomFrequencyChart(data: trends.symptomFrequency),
          const SizedBox(height: 16),
        ],
        if (trends.mealTypeDistribution.isNotEmpty) ...[
          _MealTypeChart(data: trends.mealTypeDistribution),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Signal section
// ---------------------------------------------------------------------------

class _SignalsSection extends StatelessWidget {
  const _SignalsSection({
    required this.signals,
    required this.analyzedAt,
    required this.onAnalyse,
    required this.analysisLoading,
  });

  final List<FoodSignal> signals;
  final DateTime? analyzedAt;
  final VoidCallback onAnalyse;
  final bool analysisLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Food Signals',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _timeAgo(analyzedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: analysisLoading ? null : onAnalyse,
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: const Text('Analyse now'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (signals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Keep logging — patterns will appear once you have enough data',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ...signals.map((sig) => _SignalCard(signal: sig)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual signal card
// ---------------------------------------------------------------------------

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.signal});

  final FoodSignal signal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHarmful = signal.channels.any((c) => c.direction == 'harmful');
    final accentColor = isHarmful ? Colors.orange.shade700 : Colors.green.shade700;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatCategory(signal.category),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (signal.convergent)
                    Tooltip(
                      message: 'Convergent evidence across multiple channels',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('⚡ Convergent',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Strength bar
              Row(
                children: [
                  Text(
                    'Strength',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: signal.unifiedScore.clamp(0.0, 1.0),
                        backgroundColor: theme.dividerColor,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(signal.unifiedScore * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Channel rows
              ...signal.channels.map((ch) => _ChannelRow(channel: ch)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel});

  final SignalChannel channel;

  @override
  Widget build(BuildContext context) {
    final isHarmful = channel.direction == 'harmful';
    final directionIcon = isHarmful ? '↑' : '↓';
    final directionColor =
        isHarmful ? Colors.orange.shade700 : Colors.green.shade700;

    String metric;
    if (channel.outcomeType == 'symptom' && channel.relativeRisk != null) {
      metric = 'RR ${channel.relativeRisk!.toStringAsFixed(1)}×';
    } else {
      metric = '';
    }

    String contextLabel = '';
    if (channel.peakWindowMinutes != null) {
      contextLabel = _windowLabel(channel.peakWindowMinutes);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(
            directionIcon,
            style: TextStyle(color: directionColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _formatOutcomeName(channel.outcomeName),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (contextLabel.isNotEmpty)
            Text(
              contextLabel,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (metric.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              metric,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: directionColor,
              ),
            ),
          ],
        ],
      ),
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
    final dates = data.map((p) => p.date).toList()..sort();
    final earliest = dates.first;

    final grouped = <String, List<SymptomFrequencyPoint>>{};
    for (final p in data) {
      grouped.putIfAbsent(p.symptomType, () => []).add(p);
    }
    final sortedTypes = grouped.keys.toList()..sort();

    double maxY = 1;
    for (final p in data) {
      if (p.count > maxY) maxY = p.count.toDouble();
    }

    final maxXOffset = dates.last.difference(earliest).inDays.toDouble();
    final xRange = math.max(1.0, maxXOffset);

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
        isCurved: points.length >= 2,
        color: color,
        barWidth: 2,
        dotData: const FlDotData(show: true),
      );
    }).toList();

    return LineChart(
      LineChartData(
        lineBarsData: lines,
        minX: 0,
        maxX: xRange,
        minY: 0,
        maxY: maxY + 1,
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                if (value != value.floorToDouble()) return const SizedBox();
                return Text(value.toInt().toString(),
                    style: const TextStyle(fontSize: 10));
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final date = earliest.add(Duration(days: value.toInt()));
                return Text('${date.month}/${date.day}',
                    style: const TextStyle(fontSize: 9));
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart 2 — Meal Type Distribution (PieChart)
// ---------------------------------------------------------------------------

class _MealTypeChart extends StatelessWidget {
  const _MealTypeChart({required this.data});

  final Map<String, int> data;

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
              child: () {
                final total = data.values.fold(0, (sum, v) => sum + v);
                if (data.isEmpty || total == 0) {
                  return const Center(child: Text('No meal data'));
                }
                return _buildChart(total);
              }(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(int total) {
    final entries = data.entries.toList();
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
