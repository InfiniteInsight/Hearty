import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/models/meal_log.dart';
import '../../../core/api/models/symptom_log.dart';
import '../../../core/util/meal_label.dart';
import '../../../core/api/providers/meals_provider.dart';
import '../../../core/api/providers/symptoms_provider.dart';

// ---------------------------------------------------------------------------
// Top-level helpers
// ---------------------------------------------------------------------------

String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final hour = local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour < 12 ? 'AM' : 'PM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:$minute $period';
}

String _dateHeader(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final entryDate = DateTime(local.year, local.month, local.day);

  if (entryDate == today) return 'Today';
  if (entryDate == yesterday) return 'Yesterday';

  const months = [
    '',
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[local.month]} ${local.day}';
}

// ---------------------------------------------------------------------------
// Entry types for the merged history timeline
// ---------------------------------------------------------------------------

sealed class _HistoryEntry {
  String get id;
  DateTime get loggedAt;

  bool matchesSearch(String query) {
    if (query.isEmpty) return true;
    return _searchText().toLowerCase().contains(query.toLowerCase());
  }

  String _searchText();
}

final class _MealEntry extends _HistoryEntry {
  final MealLog meal;
  _MealEntry(this.meal);

  @override
  String get id => meal.id;

  @override
  DateTime get loggedAt => meal.loggedAt;

  @override
  String _searchText() => '${meal.description} ${meal.foods.join(' ')}';
}

final class _SymptomEntry extends _HistoryEntry {
  final SymptomLog symptom;
  _SymptomEntry(this.symptom);

  @override
  String get id => symptom.id;

  @override
  DateTime get loggedAt => symptom.loggedAt;

  @override
  String _searchText() => symptom.description;
}

// ---------------------------------------------------------------------------
// Filter type
// ---------------------------------------------------------------------------

enum _HistoryFilter { all, meals, symptoms }

// ---------------------------------------------------------------------------
// HistoryScreen
// ---------------------------------------------------------------------------

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _HistoryFilter _activeFilter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mealsAsync = ref.watch(mealsProvider);
    final symptomsAsync = ref.watch(symptomsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          _SearchBar(controller: _searchController, query: _searchQuery),
          _FilterRow(
            activeFilter: _activeFilter,
            onFilterChanged: (f) => setState(() => _activeFilter = f),
          ),
          Expanded(
            child: _buildBody(context, mealsAsync, symptomsAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<MealLog>> mealsAsync,
    AsyncValue<List<SymptomLog>> symptomsAsync,
  ) {
    if (mealsAsync.isLoading || symptomsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (mealsAsync.hasError || symptomsAsync.hasError) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.invalidate(mealsProvider);
          ref.invalidate(symptomsProvider);
        },
        child: const Center(
          child: Text('Failed to load — tap to retry'),
        ),
      );
    }

    final meals = mealsAsync.value ?? [];
    final symptoms = symptomsAsync.value ?? [];

    final List<_HistoryEntry> allEntries = [
      for (final m in meals) _MealEntry(m),
      for (final s in symptoms) _SymptomEntry(s),
    ];

    final filtered = allEntries.where((e) {
      return switch (_activeFilter) {
        _HistoryFilter.all => true,
        _HistoryFilter.meals => e is _MealEntry,
        _HistoryFilter.symptoms => e is _SymptomEntry,
      };
    }).toList();

    final searched = filtered
        .where((e) => e.matchesSearch(_searchQuery))
        .toList();

    searched.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));

    if (searched.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.black26),
            SizedBox(height: 12),
            Text('No entries found'),
          ],
        ),
      );
    }

    final List<Widget> items = [];
    String? lastHeader;

    for (final entry in searched) {
      final header = _dateHeader(entry.loggedAt);
      if (header != lastHeader) {
        lastHeader = header;
        items.add(_DateHeader(label: header));
      }
      items.add(_buildEntry(context, entry));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }

  Widget _buildEntry(BuildContext context, _HistoryEntry entry) {
    return switch (entry) {
      _MealEntry(:final meal) => _MealRow(meal: meal),
      _SymptomEntry(:final symptom) => _SymptomRow(symptom: symptom),
    };
  }
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;

  const _SearchBar({required this.controller, required this.query});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Search entries…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: controller.clear,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chips row
// ---------------------------------------------------------------------------

class _FilterRow extends StatelessWidget {
  final _HistoryFilter activeFilter;
  final ValueChanged<_HistoryFilter> onFilterChanged;

  const _FilterRow({
    required this.activeFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          _chip(context, _HistoryFilter.all, 'All'),
          const SizedBox(width: 8),
          _chip(context, _HistoryFilter.meals, 'Meals'),
          const SizedBox(width: 8),
          _chip(context, _HistoryFilter.symptoms, 'Symptoms'),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, _HistoryFilter filter, String label) {
    return FilterChip(
      label: Text(label),
      selected: activeFilter == filter,
      onSelected: (_) => onFilterChanged(filter),
    );
  }
}

// ---------------------------------------------------------------------------
// Date header
// ---------------------------------------------------------------------------

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry rows
// ---------------------------------------------------------------------------

class _MealRow extends StatelessWidget {
  final MealLog meal;
  const _MealRow({required this.meal});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.restaurant),
      title: Text(mealTimelineTitle(meal.foods, meal.description)),
      subtitle: Text(_formatTime(meal.loggedAt)),
      trailing: Chip(
        label: Text(
          _capitalize(meal.mealType),
          style: const TextStyle(fontSize: 12),
        ),
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
      ),
      onTap: () => context.push('/log/${meal.id}'),
    );
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

class _SymptomRow extends StatelessWidget {
  final SymptomLog symptom;
  const _SymptomRow({required this.symptom});

  static Color _severityColor(int severity) {
    if (severity <= 3) return Colors.amber;
    if (severity <= 6) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(symptom.severity);
    return ListTile(
      leading: Icon(Icons.warning_amber_rounded, color: color),
      title: Text(symptom.description),
      subtitle: Text(_formatTime(symptom.loggedAt)),
      trailing: Chip(
        label: Text(
          '${symptom.severity}/10',
          style: TextStyle(fontSize: 12, color: color),
        ),
        backgroundColor: color.withValues(alpha: 0.15),
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
      ),
      onTap: () => context.push('/log/${symptom.id}'),
    );
  }
}
