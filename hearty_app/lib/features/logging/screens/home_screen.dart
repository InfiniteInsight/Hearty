import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/confirm_delete_dialog.dart';
import '../../../core/api/providers/meals_provider.dart';
import '../../../core/api/providers/symptoms_provider.dart';
import '../../../core/api/providers/voice_queue_provider.dart';
import '../../../core/api/models/meal_log.dart';
import '../../../core/api/models/symptom_log.dart';
import '../../../core/api/hearty_api_client.dart';
import '../../../core/offline/local_meal_dao.dart';
import '../../../core/offline/local_symptom_dao.dart';
import '../../../core/offline/offline_database.dart';
import '../../../core/sync/sync_service.dart';
import '../../checkin/widgets/home_checkin_banner.dart';

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

final class _VoiceQueueEntry extends _TimelineEntry {
  final LocalVoiceQueueData item;
  _VoiceQueueEntry(this.item);
  @override
  DateTime get loggedAt =>
      DateTime.fromMillisecondsSinceEpoch(item.loggedAt);
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
    final voiceQueueAsync = ref.watch(voiceQueueProvider);

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
              const HomeCheckinBanner(),
              Expanded(
                child: _buildBody(
                    context, mealsAsync, symptomsAsync, voiceQueueAsync),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/log'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<MealLog>> mealsAsync,
    AsyncValue<List<SymptomLog>> symptomsAsync,
    AsyncValue<List<LocalVoiceQueueData>> voiceQueueAsync,
  ) {
    // Show spinner while any provider is loading.
    if (mealsAsync.isLoading || symptomsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show error state when any provider has failed.
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
    // voiceQueue loading/error is non-blocking — show empty list on failure.
    final voiceQueue = voiceQueueAsync.value ?? [];

    return _TimelineBody(
      meals: meals,
      symptoms: symptoms,
      voiceQueue: voiceQueue,
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

}

// ---------------------------------------------------------------------------
// Timeline body (stateless — all data resolved)
// ---------------------------------------------------------------------------

class _TimelineBody extends StatelessWidget {
  final List<MealLog> meals;
  final List<SymptomLog> symptoms;
  final List<LocalVoiceQueueData> voiceQueue;

  const _TimelineBody({
    required this.meals,
    required this.symptoms,
    required this.voiceQueue,
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

    // Build flat timeline entries: meals + unlinked symptoms + pending voice queue.
    final List<_TimelineEntry> entries = [
      for (final m in todayMeals)
        _MealEntry(m, linkedMap[m.id] ?? const []),
      for (final s in unlinkedSymptoms) _SymptomEntry(s),
      for (final q in voiceQueue) _VoiceQueueEntry(q),
    ];

    // Sort descending (newest first).
    entries.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));

    return CustomScrollView(
      slivers: [
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
      _VoiceQueueEntry(:final item) => _VoiceQueueCard(item: item),
    };
  }
}

// ---------------------------------------------------------------------------
// Meal card
// ---------------------------------------------------------------------------

class _MealCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
          onLongPress: () => _showEntryActions(
            context, ref,
            editRoute: '/meals/edit',
            editExtra: {'id': meal.id, 'description': meal.description},
            onDelete: () async {
              await ref.read(heartyApiClientProvider).deleteMeal(meal.id);
              await ref.read(localMealDaoProvider).deleteByServerId(meal.id);
            },
          ),
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

class _SymptomRow extends ConsumerWidget {
  final SymptomLog symptom;

  const _SymptomRow({required this.symptom});

  static Color _severityColor(int severity) {
    if (severity <= 3) return Colors.amber;
    if (severity <= 6) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      onLongPress: () => _showEntryActions(
        context, ref,
        editRoute: '/symptoms/edit',
        editExtra: {
          'id': symptom.id,
          'description': symptom.description,
          'severity': symptom.severity,
          'onsetMinutes': symptom.onsetMinutes,
        },
        onDelete: () async {
          await ref.read(heartyApiClientProvider).deleteSymptom(symptom.id);
          await ref.read(localSymptomDaoProvider).deleteByServerId(symptom.id);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Voice queue pending card
// ---------------------------------------------------------------------------

class _VoiceQueueCard extends StatelessWidget {
  final LocalVoiceQueueData item;

  const _VoiceQueueCard({required this.item});

  void _showExplanation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voice note queued'),
        content: const Text(
          "Hearty couldn't reach the server when you recorded this. "
          "It'll be processed and appear here as a proper log entry once you reconnect.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedAt = DateTime.fromMillisecondsSinceEpoch(item.loggedAt);
    return ListTile(
      leading: Icon(
        Icons.mic,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        item.transcript,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(_formatTime(loggedAt)),
      trailing: IconButton(
        icon: Icon(
          Icons.help_outline,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: () => _showExplanation(context),
        tooltip: 'What is this?',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit / delete helpers
// ---------------------------------------------------------------------------

void _showEntryActions(
  BuildContext context,
  WidgetRef ref, {
  required String editRoute,
  required Map<String, dynamic> editExtra,
  required Future<void> Function() onDelete,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () {
              Navigator.of(ctx).pop();
              if (editExtra.isEmpty) {
                context.push(editRoute);
              } else {
                context.push(editRoute, extra: editExtra);
              }
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              confirmDelete(context, onDelete: onDelete);
            },
          ),
        ],
      ),
    ),
  );
}


