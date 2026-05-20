# Voice Queue Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show pending voice queue entries as placeholder cards in the home screen timeline so users can see what they dictated while offline, with a `?` button explaining why the entry hasn't been processed yet.

**Architecture:** `LocalVoiceQueueDao` gains a reactive `watchPending()` stream. A new `voiceQueueProvider` exposes that stream via Riverpod. The home screen adds a `_VoiceQueueEntry` sealed subtype and `_VoiceQueueCard` widget that render inline with the existing timeline. When `markDone()` deletes a row on sync, the stream emits and the card disappears automatically.

**Tech Stack:** Drift reactive streams (already in use), Riverpod `StreamNotifier` (same pattern as `wellbeingProvider`), Flutter `AlertDialog` for the `?` explanation.

**Spec:** `docs/superpowers/specs/2026-05-18-voice-queue-visibility-design.md`

---

## File Map

**Modify:**
- `lib/core/offline/local_voice_queue_dao.dart` — add `watchPending()` stream method
- `test/core/offline/local_voice_queue_dao_test.dart` — add `watchPending` test
- `lib/features/logging/screens/home_screen.dart` — add `_VoiceQueueEntry`, `_VoiceQueueCard`, wire provider

**Create:**
- `lib/core/api/providers/voice_queue_provider.dart` — `VoiceQueueNotifier` StreamNotifier

---

## Task 1: Add `watchPending()` to LocalVoiceQueueDao

**Files:**
- Modify: `lib/core/offline/local_voice_queue_dao.dart`
- Modify: `test/core/offline/local_voice_queue_dao_test.dart`

- [ ] **Step 1: Write the failing test**

Add one test to the existing test file at `test/core/offline/local_voice_queue_dao_test.dart`. Append it after the existing `markFailed` test:

```dart
  test('watchPending emits pending entries and updates when one is removed', () async {
    await dao.insertPending(
      id: 'vq-watch-1',
      transcript: 'I had oatmeal',
      loggedAt: DateTime.now(),
    );
    await dao.insertPending(
      id: 'vq-watch-2',
      transcript: 'And a coffee',
      loggedAt: DateTime.now(),
    );

    // First emission: both entries present.
    final first = await dao.watchPending().first;
    expect(first.length, 2);

    // After markDone, stream should emit with one entry removed.
    await dao.markDone('vq-watch-1');
    final second = await dao.watchPending().first;
    expect(second.length, 1);
    expect(second.first.id, 'vq-watch-2');
  });
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd hearty_app && flutter test test/core/offline/local_voice_queue_dao_test.dart
```

Expected: Error — `The method 'watchPending' isn't defined`.

- [ ] **Step 3: Implement `watchPending()`**

In `lib/core/offline/local_voice_queue_dao.dart`, add the method after `insertPending`:

```dart
  Stream<List<LocalVoiceQueueData>> watchPending() {
    return (select(db.localVoiceQueue)
          ..where((v) => v.syncStatus.equals('pending'))
          ..orderBy([(v) => OrderingTerm.desc(v.loggedAt)]))
        .watch();
  }
```

The full file should now look like:

```dart
// lib/core/offline/local_voice_queue_dao.dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_database.dart';

class LocalVoiceQueueDao extends DatabaseAccessor<OfflineDatabase> {
  LocalVoiceQueueDao(super.db);

  Future<void> insertPending({
    required String id,
    required String transcript,
    required DateTime loggedAt,
  }) {
    return db.into(db.localVoiceQueue).insert(
          LocalVoiceQueueCompanion(
            id: Value(id),
            transcript: Value(transcript),
            loggedAt: Value(loggedAt.millisecondsSinceEpoch),
            syncStatus: const Value('pending'),
          ),
        );
  }

  Stream<List<LocalVoiceQueueData>> watchPending() {
    return (select(db.localVoiceQueue)
          ..where((v) => v.syncStatus.equals('pending'))
          ..orderBy([(v) => OrderingTerm.desc(v.loggedAt)]))
        .watch();
  }

  Future<List<LocalVoiceQueueData>> getPending() {
    return (select(db.localVoiceQueue)
          ..where((v) => v.syncStatus.equals('pending'))
          ..orderBy([(v) => OrderingTerm.asc(v.loggedAt)]))
        .get();
  }

  Future<void> markDone(String id) {
    return (delete(db.localVoiceQueue)..where((v) => v.id.equals(id))).go();
  }

  Future<void> markFailed(String id) {
    return (update(db.localVoiceQueue)..where((v) => v.id.equals(id)))
        .write(const LocalVoiceQueueCompanion(syncStatus: Value('failed')));
  }
}

final localVoiceQueueDaoProvider = Provider<LocalVoiceQueueDao>((ref) {
  return LocalVoiceQueueDao(ref.watch(offlineDatabaseProvider));
});
```

- [ ] **Step 4: Run all voice queue tests to confirm they pass**

```bash
cd hearty_app && flutter test test/core/offline/local_voice_queue_dao_test.dart
```

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/lib/core/offline/local_voice_queue_dao.dart \
        hearty_app/test/core/offline/local_voice_queue_dao_test.dart
git commit -m "feat: add watchPending() stream to LocalVoiceQueueDao"
```

---

## Task 2: VoiceQueueProvider

**Files:**
- Create: `lib/core/api/providers/voice_queue_provider.dart`

- [ ] **Step 1: Create the provider**

```dart
// lib/core/api/providers/voice_queue_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../offline/local_voice_queue_dao.dart';
import '../../offline/offline_database.dart';

class VoiceQueueNotifier
    extends StreamNotifier<List<LocalVoiceQueueData>> {
  @override
  Stream<List<LocalVoiceQueueData>> build() {
    return ref.watch(localVoiceQueueDaoProvider).watchPending();
  }
}

final voiceQueueProvider =
    StreamNotifierProvider<VoiceQueueNotifier, List<LocalVoiceQueueData>>(
        VoiceQueueNotifier.new);
```

- [ ] **Step 2: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/core/api/providers/voice_queue_provider.dart
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/core/api/providers/voice_queue_provider.dart
git commit -m "feat: add VoiceQueueProvider streaming pending voice queue entries"
```

---

## Task 3: Wire into Home Screen

**Files:**
- Modify: `lib/features/logging/screens/home_screen.dart`

- [ ] **Step 1: Add the import**

At the top of `lib/features/logging/screens/home_screen.dart`, add alongside the existing provider imports:

```dart
import '../../../core/api/providers/voice_queue_provider.dart';
import '../../../core/offline/offline_database.dart';
```

- [ ] **Step 2: Add `_VoiceQueueEntry` to the sealed class**

After the existing `_WellbeingEntry` class (around line 56), add:

```dart
final class _VoiceQueueEntry extends _TimelineEntry {
  final LocalVoiceQueueData item;
  _VoiceQueueEntry(this.item);
  @override
  DateTime get loggedAt =>
      DateTime.fromMillisecondsSinceEpoch(item.loggedAt);
}
```

- [ ] **Step 3: Watch `voiceQueueProvider` in `_HomeScreenState.build()`**

In `_HomeScreenState.build()`, add after the existing three provider watches:

```dart
final voiceQueueAsync = ref.watch(voiceQueueProvider);
```

Pass it into `_buildBody`:

```dart
child: _buildBody(
    context, mealsAsync, symptomsAsync, wellbeingAsync, voiceQueueAsync),
```

- [ ] **Step 4: Update `_buildBody` signature and loading/error logic**

Replace the existing `_buildBody` method signature and guards:

```dart
  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<MealLog>> mealsAsync,
    AsyncValue<List<SymptomLog>> symptomsAsync,
    AsyncValue<List<WellbeingLog>> wellbeingAsync,
    AsyncValue<List<LocalVoiceQueueData>> voiceQueueAsync,
  ) {
    if (mealsAsync.isLoading ||
        symptomsAsync.isLoading ||
        wellbeingAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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
    final voiceQueue = voiceQueueAsync.value ?? [];

    return _TimelineBody(
      meals: meals,
      symptoms: symptoms,
      wellbeing: wellbeing,
      voiceQueue: voiceQueue,
    );
  }
```

Note: `voiceQueueAsync` loading/error states are intentionally not blocking — if it fails to load, the timeline shows without pending cards rather than showing an error screen.

- [ ] **Step 5: Update `_TimelineBody` to accept and render voice queue entries**

Add `voiceQueue` to the constructor and merge it into the entries list. Replace the existing `_TimelineBody` class:

```dart
class _TimelineBody extends StatelessWidget {
  final List<MealLog> meals;
  final List<SymptomLog> symptoms;
  final List<WellbeingLog> wellbeing;
  final List<LocalVoiceQueueData> voiceQueue;

  const _TimelineBody({
    required this.meals,
    required this.symptoms,
    required this.wellbeing,
    required this.voiceQueue,
  });

  static bool _isToday(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final todayMeals = meals.where((m) => _isToday(m.loggedAt)).toList();
    final todaySymptoms =
        symptoms.where((s) => _isToday(s.loggedAt)).toList();
    final todayWellbeing =
        wellbeing.where((w) => _isToday(w.loggedAt)).toList();

    final Map<String, List<SymptomLog>> linkedMap = {};
    for (final symptom in todaySymptoms) {
      if (symptom.linkedMealId != null) {
        linkedMap.putIfAbsent(symptom.linkedMealId!, () => []).add(symptom);
      }
    }

    final unlinkedSymptoms =
        todaySymptoms.where((s) => s.linkedMealId == null).toList();

    final List<_TimelineEntry> entries = [
      for (final m in todayMeals)
        _MealEntry(m, linkedMap[m.id] ?? const []),
      for (final s in unlinkedSymptoms) _SymptomEntry(s),
      for (final w in todayWellbeing) _WellbeingEntry(w),
      for (final q in voiceQueue) _VoiceQueueEntry(q),
    ];

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
      _VoiceQueueEntry(:final item) => _VoiceQueueCard(item: item),
    };
  }
}
```

- [ ] **Step 6: Add `_VoiceQueueCard` widget**

Add this widget after the `_WellbeingRow` widget at the bottom of the file:

```dart
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
```

- [ ] **Step 7: Verify the full file compiles**

```bash
cd hearty_app && flutter analyze lib/features/logging/screens/home_screen.dart
```

Expected: No errors.

- [ ] **Step 8: Run all tests**

```bash
cd hearty_app && flutter test
```

Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
git add hearty_app/lib/features/logging/screens/home_screen.dart
git commit -m "feat: show pending voice queue entries in home timeline"
```

---

## Task 4: Smoke Test

- [ ] **Step 1: Build and run**

```bash
make run
```

- [ ] **Step 2: Test online flow (no visible change)**

Dictate a voice note while online. It should be processed immediately — no pending card should appear in the timeline. The real entry (meal/symptom) should appear after the sync pull.

- [ ] **Step 3: Test offline flow**

1. Stop the API server so the app is effectively offline.
2. Dictate a voice note — you'll hear "You're offline or Hearty is down..."
3. Return to the home screen — a greyed-out card with a mic icon and your transcript should appear at the correct position in the timeline.
4. Tap the `?` button — the explanation dialog should appear.
5. Restart the API server. Within ~30 seconds the sync runs, the card disappears, and the real entry appears in its place.

- [ ] **Step 4: Commit any fixes**

```bash
git add -p
git commit -m "fix: smoke test corrections for voice queue visibility"
```
