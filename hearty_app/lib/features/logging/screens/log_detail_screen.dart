import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/models/meal_log.dart';
import '../../../core/api/models/symptom_log.dart';
import '../../../core/api/models/wellbeing_log.dart';
import '../../../core/api/providers/meals_provider.dart';
import '../../../core/api/providers/symptoms_provider.dart';
import '../../../core/api/providers/wellbeing_provider.dart';

class LogDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const LogDetailScreen({super.key, required this.id});

  @override
  ConsumerState<LogDetailScreen> createState() => _LogDetailScreenState();
}

class _LogDetailScreenState extends ConsumerState<LogDetailScreen> {
  bool _isLoading = true;
  Object? _entry; // MealLog | SymptomLog | WellbeingLog
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveEntry());
  }

  Future<void> _resolveEntry() async {
    // Check in-memory provider state first.
    final meals = ref.read(mealsProvider).valueOrNull ?? [];
    final meal = meals.where((m) => m.id == widget.id).firstOrNull;
    if (meal != null) {
      if (!mounted) return;
      setState(() {
        _entry = meal;
        _isLoading = false;
      });
      return;
    }

    final symptoms = ref.read(symptomsProvider).valueOrNull ?? [];
    final symptom = symptoms.where((s) => s.id == widget.id).firstOrNull;
    if (symptom != null) {
      if (!mounted) return;
      setState(() {
        _entry = symptom;
        _isLoading = false;
      });
      return;
    }

    final wellbeingList = ref.read(wellbeingProvider).valueOrNull ?? [];
    final wellbeing = wellbeingList.where((w) => w.id == widget.id).firstOrNull;
    if (wellbeing != null) {
      if (!mounted) return;
      setState(() {
        _entry = wellbeing;
        _isLoading = false;
      });
      return;
    }

    // Not found in any provider — attempt API fetch (meal only per spec).
    try {
      final fetched =
          await ref.read(heartyApiClientProvider).fetchMealById(widget.id);
      if (!mounted) return;
      setState(() {
        _entry = fetched;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notFound = true;
        _isLoading = false;
      });
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _formatFull(DateTime dt) {
    final month = _months[dt.month - 1];
    final day = dt.day;
    final year = dt.year;
    final rawHour = dt.hour;
    final ampm = rawHour < 12 ? 'AM' : 'PM';
    final displayHour = rawHour == 0
        ? 12
        : rawHour > 12
            ? rawHour - 12
            : rawHour;
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$month $day, $year at $displayHour:$minute $ampm';
  }

  Color _severityColor(int severity) {
    if (severity <= 2) return Colors.green;
    if (severity == 3) return Colors.amber;
    return Colors.red;
  }

  Color _wellbeingColor(int value) {
    if (value <= 2) return Colors.red;
    if (value == 3) return Colors.amber;
    return Colors.green;
  }

  IconData _mealTypeIcon(String mealType) {
    switch (mealType.toLowerCase()) {
      case 'breakfast':
        return Icons.wb_sunny;
      case 'lunch':
        return Icons.wb_cloudy;
      case 'dinner':
        return Icons.nights_stay;
      case 'snack':
        return Icons.local_cafe;
      default:
        return Icons.restaurant;
    }
  }

  String _mealTypeLabel(String mealType) {
    if (mealType.isEmpty) return 'Meal';
    return '${mealType[0].toUpperCase()}${mealType.substring(1)}';
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Log Entry')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_notFound || _entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Log Entry')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('Entry not found', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    // Resolve linked meal for symptom detail (must be in build()).
    final meals = ref.watch(mealsProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Log Entry')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: switch (_entry) {
          MealLog m => _buildMeal(m, theme, colorScheme),
          SymptomLog s => _buildSymptom(s, theme, colorScheme, meals),
          WellbeingLog w => _buildWellbeing(w, theme),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  // ─── Meal detail ─────────────────────────────────────────────────────────────

  Widget _buildMeal(
      MealLog meal, ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon + type label
        Center(
          child: Column(
            children: [
              Icon(
                _mealTypeIcon(meal.mealType),
                size: 64,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                _mealTypeLabel(meal.mealType),
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Description
        Text(
          meal.description,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // Timestamp
        Text(
          _formatFull(meal.loggedAt),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),

        // Foods
        if (meal.foods.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Foods identified', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: meal.foods.map((f) => Chip(label: Text(f))).toList(),
          ),
        ],

        // Claude note
        if (meal.claudeNote != null) ...[
          const SizedBox(height: 24),
          Text("Hearty's note", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(meal.claudeNote!),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Symptom detail ──────────────────────────────────────────────────────────

  Widget _buildSymptom(
      SymptomLog symptom, ThemeData theme, ColorScheme colorScheme,
      List<MealLog> meals) {
    final severityColor = _severityColor(symptom.severity);

    // Look up linked meal description from provider if available.
    String? linkedMealLabel;
    if (symptom.linkedMealId != null) {
      final linked =
          meals.where((m) => m.id == symptom.linkedMealId).firstOrNull;
      linkedMealLabel =
          linked != null ? linked.description : symptom.linkedMealId;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Leading icon + title
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 40,
              color: severityColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                symptom.description,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Severity
        Row(
          children: [
            Text('Severity: ${symptom.severity}/5',
                style: theme.textTheme.bodyLarge),
            const SizedBox(width: 12),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: severityColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Timestamp
        Text(
          _formatFull(symptom.loggedAt),
          style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6)),
        ),

        // Linked meal
        if (linkedMealLabel != null) ...[
          const SizedBox(height: 16),
          Text(
            'Logged after meal: $linkedMealLabel',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  // ─── Wellbeing detail ────────────────────────────────────────────────────────

  Widget _buildWellbeing(WellbeingLog wellbeing, ThemeData theme) {
    final energyColor = _wellbeingColor(wellbeing.energy);
    final moodColor = _wellbeingColor(wellbeing.mood);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon + title
        Center(
          child: Column(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 64,
                color: Colors.pink,
              ),
              const SizedBox(height: 8),
              Text('Wellbeing Check-In',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Energy row
        _buildWellbeingRow(
          theme,
          label: 'Energy',
          value: wellbeing.energy,
          color: energyColor,
        ),
        const SizedBox(height: 16),

        // Mood row
        _buildWellbeingRow(
          theme,
          label: 'Mood',
          value: wellbeing.mood,
          color: moodColor,
        ),

        // Notes
        if (wellbeing.notes != null) ...[
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(wellbeing.notes!),
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Timestamp
        Text(
          _formatFull(wellbeing.loggedAt),
          style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }

  Widget _buildWellbeingRow(
    ThemeData theme, {
    required String label,
    required int value,
    required Color color,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: theme.textTheme.bodyLarge),
        ),
        const SizedBox(width: 8),
        Text('$value', style: theme.textTheme.bodyLarge),
        const SizedBox(width: 12),
        Expanded(
          child: LinearProgressIndicator(
            value: value / 5.0,
            color: color,
            backgroundColor: color.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}
