import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../voice/providers/voice_provider.dart';
import '../../voice/screens/voice_overlay_screen.dart';
import '../../../core/api/providers/meals_provider.dart';
import '../../../core/api/providers/symptoms_provider.dart';
import '../../../core/api/providers/wellbeing_provider.dart';
import '../../../core/api/models/meal_log.dart';
import '../../../core/api/models/symptom_log.dart';
import '../../../core/api/models/wellbeing_log.dart';
import '../../../core/sync/sync_service.dart';
import '../../../app/router.dart';

// ---------------------------------------------------------------------------
// Top-level helpers
// ---------------------------------------------------------------------------

String _formatTime(DateTime dt) {
  final hour = dt.hour;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = hour < 12 ? 'AM' : 'PM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:$minute $period';
}

// ---------------------------------------------------------------------------
// Entry types for the merged timeline
// ---------------------------------------------------------------------------

sealed class _TimelineEntry {
  DateTime get loggedAt;
}

final class _MealEntry extends _TimelineEntry {
  final MealLog meal;
  // Linked symptoms are shown indented under this meal and excluded from
  // the flat list to avoid double-rendering.
  final List<SymptomLog> linkedSymptoms;
  _MealEntry(this.meal, this.linkedSymptoms);
  @override
  DateTime get loggedAt => meal.loggedAt;
}

final class _SymptomEntry extends _TimelineEntry {
  final SymptomLog symptom;
  _SymptomEntry(this.symptom);
  @override
  DateTime get loggedAt => symptom.loggedAt;
}

final class _WellbeingEntry extends _TimelineEntry {
  final WellbeingLog wellbeing;
  _WellbeingEntry(this.wellbeing);
  @override
  DateTime get loggedAt => wellbeing.loggedAt;
}

// ---------------------------------------------------------------------------
// HomeScreen
// ---------------------------------------------------------------------------

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final Stream<List<ConnectivityResult>> _connectivityStream;

  @override
  void initState() {
    super.initState();
    _connectivityStream = Connectivity().onConnectivityChanged;
  }

  @override
  Widget build(BuildContext context) {
    // Keep sync service alive and watch sync state.
    ref.watch(syncServiceProvider);
    ref.watch(pendingQueueCountProvider); // keeps provider alive; count read on-demand via ref.read
    final hasFailed = ref.watch(hasFailedQueueEntriesProvider).valueOrNull ?? false;
    final isSyncing = ref.watch(isSyncingProvider);

    final mealsAsync = ref.watch(mealsProvider);
    final symptomsAsync = ref.watch(symptomsProvider);
    final wellbeingAsync = ref.watch(wellbeingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hearty'),
        actions: [
          StreamBuilder<List<ConnectivityResult>>(
            stream: _connectivityStream,
            builder: (context, snapshot) {
              final results = snapshot.data;
              final isOffline = results != null &&
                  results.isNotEmpty &&
                  results.every((r) => r == ConnectivityResult.none);
              if (!isOffline) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: const Text('Offline'),
                  backgroundColor: Colors.amber.shade100,
                  labelStyle: TextStyle(
                    color: Colors.amber.shade900,
                    fontSize: 12,
                  ),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  onPressed: () {
                    final count =
                        ref.read(pendingQueueCountProvider).valueOrNull ?? 0;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(count == 1
                            ? '1 item queued for sync'
                            : '$count items queued for sync'),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (hasFailed) _failedBanner(context),
              Expanded(
                child: _buildBody(
                    context, mealsAsync, symptomsAsync, wellbeingAsync),
              ),
            ],
          ),
          if (isSyncing)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
      floatingActionButton: _QuickLogFab(
        onVoiceTap: () => _openVoiceOverlay(context),
        onTextTap: () => context.push('/log'),
        onCameraTap: () => context.push('/log'),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<MealLog>> mealsAsync,
    AsyncValue<List<SymptomLog>> symptomsAsync,
    AsyncValue<List<WellbeingLog>> wellbeingAsync,
  ) {
    // Show spinner while any provider is loading.
    if (mealsAsync.isLoading ||
        symptomsAsync.isLoading ||
        wellbeingAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show error state when any provider has failed.
    if (mealsAsync.hasError ||
        symptomsAsync.hasError ||
        wellbeingAsync.hasError) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.invalidate(mealsProvider);
          ref.invalidate(symptomsProvider);
          ref.invalidate(wellbeingProvider);
        },
        child: const Center(
          child: Text('Failed to load — tap to retry'),
        ),
      );
    }

    final meals = mealsAsync.value ?? [];
    final symptoms = symptomsAsync.value ?? [];
    final wellbeing = wellbeingAsync.value ?? [];

    return _TimelineBody(
      meals: meals,
      symptoms: symptoms,
      wellbeing: wellbeing,
    );
  }

  Widget _failedBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFailedDialog(context),
      child: Container(
        width: double.infinity,
        color: Colors.red.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade800, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Some logs couldn't sync — tap to review.",
                style: TextStyle(color: Colors.red.shade900, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFailedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsynced logs'),
        content: const Text(
          'Some entries failed to sync while the server was unavailable. '
          'Retry to upload them now, or dismiss to discard them.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(syncServiceProvider).dismissFailed();
            },
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(syncServiceProvider).retryFailed();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _openVoiceOverlay(BuildContext context) async {
    ref.read(voiceProvider.notifier).startListening();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceOverlayScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline body (stateless — all data resolved)
// ---------------------------------------------------------------------------

class _TimelineBody extends StatelessWidget {
  final List<MealLog> meals;
  final List<SymptomLog> symptoms;
  final List<WellbeingLog> wellbeing;

  const _TimelineBody({
    required this.meals,
    required this.symptoms,
    required this.wellbeing,
  });

  /// Returns true if [dt] falls on today's date (date parts only).
  static bool _isToday(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    return local.year == now.year && local.month == now.month && local.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    // Filter to today's entries.
    final todayMeals = meals.where((m) => _isToday(m.loggedAt)).toList();
    final todaySymptoms =
        symptoms.where((s) => _isToday(s.loggedAt)).toList();
    final todayWellbeing =
        wellbeing.where((w) => _isToday(w.loggedAt)).toList();

    // Build a lookup: mealId → list of linked symptoms.
    final Map<String, List<SymptomLog>> linkedMap = {};
    for (final symptom in todaySymptoms) {
      if (symptom.linkedMealId != null) {
        linkedMap.putIfAbsent(symptom.linkedMealId!, () => []).add(symptom);
      }
    }

    // Symptoms that are NOT linked to any meal appear in the flat timeline.
    final unlinkedSymptoms =
        todaySymptoms.where((s) => s.linkedMealId == null).toList();

    // Build flat timeline entries: meals + unlinked symptoms + wellbeing.
    final List<_TimelineEntry> entries = [
      for (final m in todayMeals)
        _MealEntry(m, linkedMap[m.id] ?? const []),
      for (final s in unlinkedSymptoms) _SymptomEntry(s),
      for (final w in todayWellbeing) _WellbeingEntry(w),
    ];

    // Sort descending (newest first).
    entries.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _WellbeingSnapshotCard(wellbeingEntries: todayWellbeing),
        ),
        if (entries.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No entries yet today.\nTap + to log a meal or symptom.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildEntry(context, entries[index]),
              childCount: entries.length,
            ),
          ),
      ],
    );
  }

  Widget _buildEntry(BuildContext context, _TimelineEntry entry) {
    return switch (entry) {
      _MealEntry(:final meal, :final linkedSymptoms) =>
        _MealCard(meal: meal, linkedSymptoms: linkedSymptoms),
      _SymptomEntry(:final symptom) => _SymptomRow(symptom: symptom),
      _WellbeingEntry(:final wellbeing) =>
        _WellbeingRow(wellbeing: wellbeing),
    };
  }
}

// ---------------------------------------------------------------------------
// Wellbeing snapshot card
// ---------------------------------------------------------------------------

class _WellbeingSnapshotCard extends StatelessWidget {
  final List<WellbeingLog> wellbeingEntries;

  const _WellbeingSnapshotCard({required this.wellbeingEntries});

  @override
  Widget build(BuildContext context) {
    if (wellbeingEntries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.pushNamed(Routes.wellbeingLog),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.favorite_border,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Log your morning wellbeing'),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final avgEnergy =
        wellbeingEntries.map((w) => w.energy).reduce((a, b) => a + b) /
            wellbeingEntries.length;
    final avgMood =
        wellbeingEntries.map((w) => w.mood).reduce((a, b) => a + b) /
            wellbeingEntries.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's wellbeing",
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text('Energy  ${avgEnergy.toStringAsFixed(1)} / 5'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.sentiment_satisfied_alt,
                      color: Colors.pink),
                  const SizedBox(width: 8),
                  Text('Mood  ${avgMood.toStringAsFixed(1)} / 5'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Meal card
// ---------------------------------------------------------------------------

class _MealCard extends StatelessWidget {
  final MealLog meal;
  final List<SymptomLog> linkedSymptoms;

  const _MealCard({required this.meal, required this.linkedSymptoms});

  static IconData _mealTypeIcon(String mealType) {
    return switch (mealType.toLowerCase()) {
      'breakfast' => Icons.wb_sunny,
      'lunch' => Icons.wb_cloudy,
      'dinner' => Icons.nights_stay,
      _ => Icons.local_dining, // snack / other
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(_mealTypeIcon(meal.mealType)),
          title: Text(meal.description),
          subtitle: Text(_formatTime(meal.loggedAt)),
          trailing: meal.claudeNote != null
              ? const Icon(Icons.info_outline, size: 20)
              : null,
          onTap: () => context.push('/log/${meal.id}'),
        ),
        // Linked symptoms indented under this meal.
        for (final symptom in linkedSymptoms)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: _SymptomRow(symptom: symptom),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Symptom row
// ---------------------------------------------------------------------------

class _SymptomRow extends StatelessWidget {
  final SymptomLog symptom;

  const _SymptomRow({required this.symptom});

  static Color _severityColor(int severity) {
    if (severity <= 2) return Colors.amber;
    if (severity == 3) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.warning_amber_rounded,
        color: _severityColor(symptom.severity),
      ),
      title: Text(symptom.description),
      subtitle: Text(_formatTime(symptom.loggedAt)),
      trailing: Chip(
        label: Text(
          '${symptom.severity}',
          style: const TextStyle(fontSize: 12),
        ),
        backgroundColor: _severityColor(symptom.severity).withValues(alpha: 0.15),
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
      ),
      onTap: () => context.push('/log/${symptom.id}'),
    );
  }
}

// ---------------------------------------------------------------------------
// Wellbeing row
// ---------------------------------------------------------------------------

class _WellbeingRow extends StatelessWidget {
  final WellbeingLog wellbeing;

  const _WellbeingRow({required this.wellbeing});

  static (Color bg, Color fg) _scale(int v) {
    if (v <= 2) return (Colors.red.shade100, Colors.red.shade800);
    if (v == 3) return (Colors.orange.shade100, Colors.orange.shade800);
    return (Colors.green.shade100, Colors.green.shade800);
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [_formatTime(wellbeing.loggedAt)];
    if (wellbeing.notes != null && wellbeing.notes!.isNotEmpty) {
      subtitleParts.add(wellbeing.notes!);
    }

    final (energyBg, energyFg) = _scale(wellbeing.energy);
    final (moodBg, moodFg) = _scale(wellbeing.mood);

    return ListTile(
      leading: const Icon(Icons.favorite_rounded, color: Colors.pink),
      title: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          Chip(
            label: Text(
              '⚡ ${wellbeing.energy}/5',
              style: TextStyle(color: energyFg, fontSize: 12),
            ),
            backgroundColor: energyBg,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            side: BorderSide.none,
          ),
          Chip(
            label: Text(
              '😊 ${wellbeing.mood}/5',
              style: TextStyle(color: moodFg, fontSize: 12),
            ),
            backgroundColor: moodBg,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            side: BorderSide.none,
          ),
        ],
      ),
      subtitle: Text(subtitleParts.join(' · ')),
      onTap: () => context.push('/log/${wellbeing.id}'),
    );
  }
}

// ---------------------------------------------------------------------------
// FAB — unchanged from original
// ---------------------------------------------------------------------------

class _QuickLogFab extends StatefulWidget {
  final VoidCallback onVoiceTap;
  final VoidCallback onTextTap;
  final VoidCallback onCameraTap;

  const _QuickLogFab({
    required this.onVoiceTap,
    required this.onTextTap,
    required this.onCameraTap,
  });

  @override
  State<_QuickLogFab> createState() => _QuickLogFabState();
}

class _QuickLogFabState extends State<_QuickLogFab> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_expanded) ...[
          _SubFab(icon: Icons.mic, label: 'Voice', onTap: () {
            setState(() => _expanded = false);
            widget.onVoiceTap();
          }),
          const SizedBox(height: 8),
          _SubFab(icon: Icons.edit, label: 'Text', onTap: () {
            setState(() => _expanded = false);
            widget.onTextTap();
          }),
          const SizedBox(height: 8),
          _SubFab(icon: Icons.camera_alt, label: 'Camera', onTap: () {
            setState(() => _expanded = false);
            widget.onCameraTap();
          }),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Icon(_expanded ? Icons.close : Icons.add),
        ),
      ],
    );
  }
}

class _SubFab extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubFab({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xDD000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}
