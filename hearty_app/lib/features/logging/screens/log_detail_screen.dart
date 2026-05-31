import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/offline/local_meal_dao.dart';
import '../../../core/offline/local_symptom_dao.dart';
import '../../../core/api/models/meal_log.dart';
import '../../../core/api/models/symptom_log.dart';
import '../../../core/api/providers/meals_provider.dart';
import '../../../core/api/providers/symptoms_provider.dart';
import '../../../core/widgets/confirm_delete_dialog.dart';

class LogDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const LogDetailScreen({super.key, required this.id});

  @override
  ConsumerState<LogDetailScreen> createState() => _LogDetailScreenState();
}

class _LogDetailScreenState extends ConsumerState<LogDetailScreen> {
  bool _isLoading = true;
  Object? _entry; // MealLog | SymptomLog
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
    if (severity <= 3) return Colors.green;
    if (severity <= 6) return Colors.amber;
    return Colors.red;
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

    // Watch providers so the UI updates reactively when the Drift
    // stream emits after an edit or delete (today's entries only; historical
    // entries fall back to the locally cached _entry).
    final meals = ref.watch(mealsProvider).valueOrNull ?? [];
    final symptoms = ref.watch(symptomsProvider).valueOrNull ?? [];

    final liveEntry = switch (_entry) {
      MealLog _ => meals.where((m) => m.id == widget.id).firstOrNull ?? _entry,
      SymptomLog _ =>
        symptoms.where((s) => s.id == widget.id).firstOrNull ?? _entry,
      _ => _entry,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Entry'),
        actions: [
          switch (liveEntry) {
            MealLog m => IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () async {
                  await context.push(
                    '/meals/edit',
                    extra: {
                      'id': m.id,
                      'description': m.description,
                      'foods': m.foods,
                    },
                  );
                  if (mounted) _resolveEntry();
                },
              ),
            SymptomLog s => IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () async {
                  await context.push(
                    '/symptoms/edit',
                    extra: {
                      'id': s.id,
                      'description': s.description,
                      'severity': s.severity,
                      'onsetMinutes': s.onsetMinutes,
                    },
                  );
                  if (mounted) _resolveEntry();
                },
              ),
            _ => const SizedBox.shrink(),
          },
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            tooltip: 'Delete',
            onPressed: () => switch (liveEntry) {
              MealLog m => confirmDelete(context, popAfter: true, onDelete: () async {
                  await ref.read(heartyApiClientProvider).deleteMeal(m.id);
                  await ref.read(localMealDaoProvider).deleteByServerId(m.id);
                }),
              SymptomLog s => confirmDelete(context, popAfter: true, onDelete: () async {
                  await ref.read(heartyApiClientProvider).deleteSymptom(s.id);
                  await ref.read(localSymptomDaoProvider).deleteByServerId(s.id);
                }),
              _ => Future.value(),
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: switch (liveEntry) {
          MealLog m => _buildMeal(m, theme, colorScheme),
          SymptomLog s => _buildSymptom(s, theme, colorScheme, meals),
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
            Text('Severity: ${symptom.severity}/10',
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

}
