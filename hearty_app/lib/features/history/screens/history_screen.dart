import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/models/meal_log.dart';
import '../../../core/api/models/symptom_log.dart';
import '../../../core/util/meal_label.dart';

// ---------------------------------------------------------------------------
// Top-level helpers
// ---------------------------------------------------------------------------

DateTime _dateOnly(DateTime dt) {
  final local = dt.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final hour = local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour < 12 ? 'AM' : 'PM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:$minute $period';
}

/// Two-line variant for the day timeline ("1:04\nPM").
String _formatTimeStacked(DateTime dt) {
  final local = dt.toLocal();
  final hour = local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour < 12 ? 'AM' : 'PM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:$minute\n$period';
}

String _dateHeader(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final entryDate = _dateOnly(dt);

  if (entryDate == today) return 'Today';
  if (entryDate == yesterday) return 'Yesterday';

  final local = dt.toLocal();
  return '${_monthAbbrevs[local.month]} ${local.day}';
}

const _monthAbbrevs = [
  '',
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _monthNames = [
  '',
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _weekdayNames = [
  '',
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

// ---------------------------------------------------------------------------
// Data — fetch the visible month from the API
// ---------------------------------------------------------------------------

final monthEntriesProvider = FutureProvider.autoDispose
    .family<List<_HistoryEntry>, DateTime>((ref, month) async {
  final api = ref.read(heartyApiClientProvider);
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1); // exclusive next-month start
  final meals = await api.fetchMeals(start: start, end: end);
  final symptoms = await api.fetchSymptoms(start: start, end: end);
  return [
    for (final m in meals) _MealEntry(m),
    for (final s in symptoms) _SymptomEntry(s),
  ];
});

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

bool _passesFilter(_HistoryEntry e, _HistoryFilter filter) {
  return switch (filter) {
    _HistoryFilter.all => true,
    _HistoryFilter.meals => e is _MealEntry,
    _HistoryFilter.symptoms => e is _SymptomEntry,
  };
}

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

  late DateTime _month;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _prevMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(monthEntriesProvider(_month));

    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('History')),
          body: Column(
            children: [
              _SearchBar(controller: _searchController, query: _searchQuery),
              _FilterRow(
                activeFilter: _activeFilter,
                onFilterChanged: (f) => setState(() => _activeFilter = f),
              ),
              Expanded(
                child: entriesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        ref.invalidate(monthEntriesProvider(_month)),
                    child: const Center(
                      child: Text(
                        'Failed to load — tap to retry',
                        style: TextStyle(color: Aurora.textSecondary),
                      ),
                    ),
                  ),
                  data: (entries) => _searchQuery.isNotEmpty
                      ? _buildSearchResults(context, entries)
                      : _buildCalendarMode(context, entries),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Search mode: flat grouped results -----------------------------------

  Widget _buildSearchResults(
    BuildContext context,
    List<_HistoryEntry> entries,
  ) {
    final results = entries
        .where((e) => _passesFilter(e, _activeFilter))
        .where((e) => e.matchesSearch(_searchQuery))
        .toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));

    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No entries found',
          style: TextStyle(color: Aurora.textMuted),
        ),
      );
    }

    final items = <Widget>[];
    String? lastHeader;
    for (final entry in results) {
      final header = _dateHeader(entry.loggedAt);
      if (header != lastHeader) {
        lastHeader = header;
        items.add(_DateHeader(label: header));
      }
      items.add(_EntryCard(entry: entry));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: items,
    );
  }

  // --- Calendar mode -------------------------------------------------------

  Widget _buildCalendarMode(
    BuildContext context,
    List<_HistoryEntry> entries,
  ) {
    final daysWithEntries = <DateTime>{
      for (final e in entries) _dateOnly(e.loggedAt),
    };

    final dayEntries = entries
        .where((e) => _dateOnly(e.loggedAt) == _selectedDay)
        .where((e) => _passesFilter(e, _activeFilter))
        .toList()
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

    final label =
        '${_weekdayNames[_selectedDay.weekday]}, '
        '${_monthNames[_selectedDay.month]} ${_selectedDay.day}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MonthCalendar(
            month: _month,
            selectedDay: _selectedDay,
            daysWithEntries: daysWithEntries,
            onDayTap: (d) => setState(() => _selectedDay = d),
            onPrevMonth: _prevMonth,
            onNextMonth: _nextMonth,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              color: Aurora.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (dayEntries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No entries this day.',
                  style: TextStyle(color: Aurora.textMuted),
                ),
              ),
            )
          else
            _DayTimeline(entries: dayEntries),
        ],
      ),
    );
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
        style: const TextStyle(color: Aurora.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search entries…',
          hintStyle: const TextStyle(color: Aurora.textMuted),
          prefixIcon: const Icon(Icons.search, color: Aurora.textMuted),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Aurora.textMuted),
                  onPressed: controller.clear,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Aurora.glassFill,
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
          _chip(_HistoryFilter.all, 'All'),
          const SizedBox(width: 8),
          _chip(_HistoryFilter.meals, 'Meals'),
          const SizedBox(width: 8),
          _chip(_HistoryFilter.symptoms, 'Symptoms'),
        ],
      ),
    );
  }

  Widget _chip(_HistoryFilter filter, String label) {
    final selected = activeFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onFilterChanged(filter),
      backgroundColor: Aurora.glassFill,
      selectedColor: Aurora.accentGreen,
      side: const BorderSide(color: Aurora.glassBorder),
      labelStyle: TextStyle(
        color: selected ? Aurora.bgBottom : Aurora.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      showCheckmark: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Date header (search mode grouping)
// ---------------------------------------------------------------------------

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: Aurora.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Month calendar
// ---------------------------------------------------------------------------

class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDay;
  final Set<DateTime> daysWithEntries;
  final ValueChanged<DateTime> onDayTap;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const _MonthCalendar({
    required this.month,
    required this.selectedDay,
    required this.daysWithEntries,
    required this.onDayTap,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final leadingEmpty = firstOfMonth.weekday % 7; // Sunday-start offset
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final cells = <Widget>[];
    for (var i = 0; i < leadingEmpty; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      cells.add(_DayCell(
        day: day,
        hasEntries: daysWithEntries.contains(date),
        isSelected: date == selectedDay,
        isToday: date == today,
        onTap: () => onDayTap(date),
      ));
    }

    return Column(
      children: [
        // Header: ‹  Month Year  ›
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Aurora.textSecondary),
              onPressed: onPrevMonth,
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${_monthNames[month.month]} ${month.year}',
                  style: const TextStyle(
                    color: Aurora.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            IconButton(
              icon:
                  const Icon(Icons.chevron_right, color: Aurora.textSecondary),
              onPressed: onNextMonth,
            ),
          ],
        ),
        // Weekday header
        Row(
          children: [
            for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: const TextStyle(
                      color: Aurora.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool hasEntries;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.hasEntries,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? Aurora.accentGreen.withValues(alpha: 0.18)
                : Colors.transparent,
            border: isSelected
                ? Border.all(color: Aurora.accentGreen)
                : (isToday
                    ? Border.all(color: Aurora.glassBorder)
                    : null),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  color: isSelected ? Aurora.textPrimary : Aurora.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              if (hasEntries)
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Aurora.accentGreen,
                    boxShadow: [
                      BoxShadow(
                        color: Aurora.accentGreen.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(width: 4, height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day timeline
// ---------------------------------------------------------------------------

class _DayTimeline extends StatelessWidget {
  final List<_HistoryEntry> entries;
  const _DayTimeline({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          _TimelineRow(
            entry: entries[i],
            isFirst: i == 0,
            isLast: i == entries.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final _HistoryEntry entry;
  final bool isFirst;
  final bool isLast;

  const _TimelineRow({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final isMeal = entry is _MealEntry;
    final dotColor = isMeal ? Aurora.accentGreen : Aurora.accentRed;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Time column
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatTimeStacked(entry.loggedAt),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Aurora.textMuted,
                  fontSize: 11,
                  height: 1.2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Spine column
          SizedBox(
            width: 20,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: Aurora.glassBorder,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Card
          Expanded(child: _EntryCard(entry: entry)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aurora glass entry card (timeline + search results)
// ---------------------------------------------------------------------------

class _EntryCard extends StatelessWidget {
  final _HistoryEntry entry;
  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/log/${entry.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Aurora.glassFill,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Aurora.glassBorder),
        ),
        child: switch (entry) {
          _MealEntry(:final meal) => _mealContent(meal),
          _SymptomEntry(:final symptom) => _symptomContent(symptom),
        },
      ),
    );
  }

  Widget _mealContent(MealLog meal) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🍽️', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mealTimelineTitle(meal.foods, meal.description),
                style: const TextStyle(
                  color: Aurora.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(meal.loggedAt),
                style: const TextStyle(
                  color: Aurora.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _symptomContent(SymptomLog symptom) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🤢', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                symptom.description,
                style: const TextStyle(
                  color: Aurora.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(symptom.loggedAt),
                style: const TextStyle(
                  color: Aurora.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Aurora.accentRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${symptom.severity}/10',
            style: const TextStyle(
              color: Aurora.accentRed,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
