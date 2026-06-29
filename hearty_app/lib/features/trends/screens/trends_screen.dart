import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../../../core/api/models/trends_data.dart';
import '../../../core/api/providers/trends_provider.dart';
import '../widgets/trends_conversation_entry.dart';

// ---------------------------------------------------------------------------
// Aurora glass-card decoration shared by the section cards.
// ---------------------------------------------------------------------------

BoxDecoration _glassDecoration() => BoxDecoration(
      color: Aurora.glassFill,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Aurora.glassBorder),
    );

Widget _glassCard({required Widget child}) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: _glassDecoration(),
      child: child,
    );

// ---------------------------------------------------------------------------
// Direction → color/arrow. Intentional divergence from the Aurora guide:
// the guide uses emerald for both directions, but that defeats telling a
// harmful trigger from a protective food at a glance. Harmful = red ↑,
// protective = emerald ↓.
// ---------------------------------------------------------------------------

Color _directionColor(String direction) =>
    direction == 'harmful' ? Aurora.accentRed : Aurora.accentGreen;

String _directionArrow(String direction) => direction == 'harmful' ? '↑' : '↓';

// ---------------------------------------------------------------------------
// Display helpers
// ---------------------------------------------------------------------------

String _recurringLabel(List<int> yearsSeen) {
  final base = 'Seen ${yearsSeen.length} years';
  if (yearsSeen.isEmpty) return base;
  final years =
      yearsSeen.map((y) => "'${(y % 100).toString().padLeft(2, '0')}").join(' · ');
  return '$base · $years';
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

/// Top (first) channel, or null when a signal carries no channels. The badge
/// tests build [SignalCard] with an empty channel list — every channel-derived
/// piece of UI must tolerate null here.
SignalChannel? _topChannel(FoodSignal signal) =>
    signal.channels.isEmpty ? null : signal.channels.first;

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

    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('Trends')),
          body: Column(
            children: [
              // Defer-to-tap entry into the monthly trends conversation. Shown
              // regardless of trends load state, gated on the prefs flag inside.
              const TrendsConversationEntry(),
              Expanded(
                child: asyncTrends.when(
                  loading: () => const _LoadingSkeleton(),
                  error: (err, _) => Center(
                    child: GestureDetector(
                      onTap: () => ref.invalidate(trendsProvider),
                      child: const Text(
                        'Failed to load trends — tap to retry',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Aurora.accentRed),
                      ),
                    ),
                  ),
                  data: (trends) => _TrendsBody(
                    trends: trends,
                    onAnalyse: _runAnalysis,
                    analysisLoading: _analysisLoading,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton (dark glass blocks)
// ---------------------------------------------------------------------------

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: List.generate(4, (i) {
        return _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 16,
                width: 140,
                decoration: BoxDecoration(
                  color: Aurora.glassFill,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Aurora.glassFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — header + hero + ranked signals + chart sections
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
        _HeaderRow(
          analyzedAt: trends.analyzedAt,
          onAnalyse: onAnalyse,
          analysisLoading: analysisLoading,
        ),
        const SizedBox(height: 12),
        if (trends.signals.isNotEmpty) ...[
          _HeroSignal(signal: trends.signals.first),
        ],
        _SignalsSection(
          signals: trends.signals,
          analyzedAt: trends.analyzedAt,
        ),
        if (trends.resolved.isNotEmpty) ResolvedSection(resolved: trends.resolved),
        if (trends.symptomFrequency.isNotEmpty)
          _SymptomFrequencyChart(data: trends.symptomFrequency),
        if (trends.mealTypeDistribution.isNotEmpty)
          _MealTypeChart(data: trends.mealTypeDistribution),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header row — eyebrow timestamp + gradient Analyse pill
// ---------------------------------------------------------------------------

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.analyzedAt,
    required this.onAnalyse,
    required this.analysisLoading,
  });

  final DateTime? analyzedAt;
  final VoidCallback onAnalyse;
  final bool analysisLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'ANALYSED ${_timeAgo(analyzedAt).toUpperCase()}',
            style: const TextStyle(
              color: Aurora.textMuted,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GestureDetector(
          onTap: analysisLoading ? null : onAnalyse,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: Aurora.fab,
              borderRadius: BorderRadius.circular(20),
            ),
            child: analysisLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Analyse',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero "Strongest signal" callout
// ---------------------------------------------------------------------------

class _HeroSignal extends StatelessWidget {
  const _HeroSignal({required this.signal});

  final FoodSignal signal;

  @override
  Widget build(BuildContext context) {
    final top = _topChannel(signal);
    final headline = top == null
        ? signal.categoryLabel
        : '${signal.categoryLabel} → ${_formatOutcomeName(top.outcomeName)}';

    final rrColor = top == null
        ? Aurora.textPrimary
        : _directionColor(top.direction);
    final rrValue = (top?.relativeRisk != null)
        ? '${top!.relativeRisk!.toStringAsFixed(1)}×'
        : '—';
    final windowValue =
        (top?.peakWindowMinutes != null) ? _windowLabel(top!.peakWindowMinutes) : '—';
    final evidence = top != null ? '${top.evidenceCount} logs' : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Aurora.accentGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Aurora.accentGreen.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚡ STRONGEST SIGNAL',
            style: TextStyle(
              color: Aurora.accentGreen,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            style: const TextStyle(
              color: Aurora.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  value: rrValue,
                  label: 'relative risk',
                  color: rrColor,
                ),
              ),
              Expanded(
                child: _HeroStat(
                  value: windowValue,
                  label: 'peak window',
                  color: Aurora.textPrimary,
                ),
              ),
              Expanded(
                child: _HeroStat(
                  value: evidence,
                  label: 'evidence',
                  color: Aurora.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Aurora.textMuted, fontSize: 11),
        ),
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
  });

  final List<FoodSignal> signals;
  final DateTime? analyzedAt;

  @override
  Widget build(BuildContext context) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Food Signals',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Aurora.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeAgo(analyzedAt),
                style: const TextStyle(fontSize: 12, color: Aurora.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (signals.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Keep logging — patterns will appear once you have enough data',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Aurora.textSecondary, fontSize: 13),
                ),
              ),
            )
          else
            ...signals.map((sig) => SignalCard(signal: sig)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual signal card
//
// Public + keyed widgets (recurring badge, new chip, sparkline) are preserved
// for the widget tests. Renders standalone in a bare MaterialApp, so it uses
// const Aurora tokens directly rather than relying on an ancestor Theme.
// ---------------------------------------------------------------------------

class SignalCard extends StatelessWidget {
  const SignalCard({super.key, required this.signal});

  final FoodSignal signal;

  @override
  Widget build(BuildContext context) {
    final isHarmful = signal.channels.any((c) => c.direction == 'harmful');
    final barColor = isHarmful ? Aurora.accentRed : Aurora.accentGreen;
    final top = _topChannel(signal);

    // Subline: "→ Outcome · peaks ~Nmin" from the top channel.
    String? subline;
    if (top != null) {
      final parts = <String>['→ ${_formatOutcomeName(top.outcomeName)}'];
      if (top.peakWindowMinutes != null) {
        parts.add('peaks ~${top.peakWindowMinutes}min');
      }
      subline = parts.join(' · ');
    }

    final rrText = (top?.relativeRisk != null)
        ? '${_directionArrow(top!.direction)} ${top.relativeRisk!.toStringAsFixed(1)}×'
        : null;
    final rrColor = top != null ? _directionColor(top.direction) : Aurora.textPrimary;

    final logCount =
        signal.channels.fold<int>(0, (sum, c) => sum + c.evidenceCount);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Aurora.glassFill,
        border: Border.all(color: Aurora.glassBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gradient icon chip.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: Aurora.fab,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('🍽️', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signal.categoryLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Aurora.textPrimary,
                      ),
                    ),
                    if (subline != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subline,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Aurora.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (rrText != null) ...[
                const SizedBox(width: 8),
                Text(
                  rrText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: rrColor,
                  ),
                ),
              ],
            ],
          ),
          if (signal.recurring || signal.isNew) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (signal.recurring)
                  Container(
                    key: const Key('signal-recurring-badge'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Aurora.accentViolet.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _recurringLabel(signal.yearsSeen),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Aurora.accentVioletLight,
                      ),
                    ),
                  ),
                if (signal.isNew)
                  Container(
                    key: const Key('signal-new-chip'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Aurora.accentGreen.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'New this year',
                      style: TextStyle(fontSize: 11, color: Aurora.accentGreen),
                    ),
                  ),
              ],
            ),
          ],
          if (signal.recurring && signal.strengthByYear.length >= 2) ...[
            const SizedBox(height: 8),
            SizedBox(
              key: const Key('signal-sparkline'),
              height: 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final entry in (signal.strengthByYear.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key))))
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Container(
                        width: 8,
                        height:
                            (4 + 20 * entry.value.clamp(0.0, 1.0)).toDouble(),
                        decoration: BoxDecoration(
                          color: Aurora.accentVioletLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Strength bar — track in glassBorder, fill ∝ unifiedScore.
          LayoutBuilder(
            builder: (context, constraints) {
              final fillWidth =
                  constraints.maxWidth * signal.unifiedScore.clamp(0.0, 1.0);
              return Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Aurora.glassBorder,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    height: 6,
                    width: fillWidth,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          // Meta row.
          Row(
            children: [
              Text(
                'based on $logCount logs',
                style: const TextStyle(fontSize: 11, color: Aurora.textMuted),
              ),
              const Spacer(),
              if (signal.convergent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Aurora.accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '⚡ Convergent',
                    style: TextStyle(fontSize: 11, color: Aurora.accentGreen),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resolved section — "No longer flagging". Public + keyed for the tests;
// renders standalone, so it uses const Aurora tokens directly.
// ---------------------------------------------------------------------------

class ResolvedSection extends StatelessWidget {
  const ResolvedSection({super.key, required this.resolved});

  final List<ResolvedSignal> resolved;

  @override
  Widget build(BuildContext context) {
    if (resolved.isEmpty) return const SizedBox.shrink();
    final firm = resolved.where((r) => r.status == 'resolved').toList();
    final maybe =
        resolved.where((r) => r.status == 'potentially_resolved').toList();
    return Container(
      key: const Key('trends-resolved-section'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Aurora.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Aurora.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No longer flagging',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Aurora.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final r in firm)
            _ResolvedRow(
                categoryLabel: r.categoryLabel,
                label: 'Resolved',
                color: Aurora.accentGreen,
                key: Key('resolved-firm-${r.category}')),
          for (final r in maybe)
            _ResolvedRow(
                categoryLabel: r.categoryLabel,
                label: 'Possibly resolved',
                color: const Color(0xFFFFBC00),
                key: Key('resolved-maybe-${r.category}')),
        ],
      ),
    );
  }
}

class _ResolvedRow extends StatelessWidget {
  const _ResolvedRow(
      {super.key,
      required this.categoryLabel,
      required this.label,
      required this.color});

  final String categoryLabel;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
              child: Text(categoryLabel,
                  style: const TextStyle(
                      fontSize: 13, color: Aurora.textSecondary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6)),
            child: Text(label, style: TextStyle(fontSize: 11, color: color)),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Chart 1 — Symptom Frequency (30-day vertical BarChart)
//
// Sums `count` across symptom types per day → one emerald bar per day.
// ---------------------------------------------------------------------------

class _SymptomFrequencyChart extends StatelessWidget {
  const _SymptomFrequencyChart({required this.data});

  final List<SymptomFrequencyPoint> data;

  @override
  Widget build(BuildContext context) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Symptom frequency (30 days)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Aurora.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: data.isEmpty
                ? const Center(
                    child: Text('No symptom data',
                        style: TextStyle(color: Aurora.textMuted)))
                : _buildChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    // Bucket per calendar day (sum across symptom types).
    final perDay = <DateTime, int>{};
    for (final p in data) {
      final day = DateTime(p.date.year, p.date.month, p.date.day);
      perDay[day] = (perDay[day] ?? 0) + p.count;
    }
    final days = perDay.keys.toList()..sort();
    if (days.isEmpty) {
      return const Center(
        child: Text('No symptom data',
            style: TextStyle(color: Aurora.textMuted)),
      );
    }

    // 30-day window ending at the latest logged day.
    final latest = days.last;
    final start = latest.subtract(const Duration(days: 29));

    final groups = <BarChartGroupData>[];
    var maxY = 1.0;
    for (var i = 0; i < 30; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      final count = (perDay[DateTime(day.year, day.month, day.day)] ?? 0)
          .toDouble();
      if (count > maxY) maxY = count;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: count,
              color: Aurora.accentGreen,
              width: 5,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        minY: 0,
        maxY: maxY + 1,
        barGroups: groups,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                if (value != value.floorToDouble()) return const SizedBox();
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(color: Aurora.textMuted, fontSize: 10),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                // Label every ~7 days to avoid clutter.
                if (i % 7 != 0) return const SizedBox();
                final day =
                    DateTime(start.year, start.month, start.day + i);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${day.month}/${day.day}',
                    style: const TextStyle(
                        color: Aurora.textMuted, fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart 2 — Meal-type mix (horizontal stacked proportion bar)
// ---------------------------------------------------------------------------

class _MealTypeChart extends StatelessWidget {
  const _MealTypeChart({required this.data});

  final Map<String, int> data;

  static const _kSegmentColors = [
    Aurora.accentGreen, // emerald
    Aurora.accentViolet, // violet
    Color(0xFFFFBC00), // amber
    Color(0xFF03A9F4), // sky
  ];

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0, (sum, v) => sum + v);
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Meal-type mix',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Aurora.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (data.isEmpty || total == 0)
            const Center(
              child: Text('No meal data',
                  style: TextStyle(color: Aurora.textMuted)),
            )
          else
            _buildBar(total),
        ],
      ),
    );
  }

  Widget _buildBar(int total) {
    final entries = data.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 16,
            child: Row(
              children: [
                for (final entry in entries.asMap().entries)
                  Expanded(
                    flex: entry.value.value,
                    child: Container(
                      color: _kSegmentColors[
                          entry.key % _kSegmentColors.length],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final entry in entries.asMap().entries)
              _LegendDot(
                color: _kSegmentColors[entry.key % _kSegmentColors.length],
                label: '${entry.value.key} (${entry.value.value})',
              ),
          ],
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
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Aurora.textSecondary)),
      ],
    );
  }
}
