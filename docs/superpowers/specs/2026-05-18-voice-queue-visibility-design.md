# Voice Queue Visibility — Design Spec

**Date:** 2026-05-18

## Problem

When a user dictates a voice note while offline (or while the Hearty API is unreachable), the transcript is saved locally in `local_voice_queue_dao` with `syncStatus = 'pending'`. It remains invisible on the home and history screens until the API is reachable, the transcript is replayed through `/api/chat`, and the next sync pull brings the resulting entry into the local meal/symptom/wellbeing tables. The user has no indication that their entry was captured.

## Scope

Home screen only. History screen is out of scope — pending voice items have not yet been classified, so they don't belong in a type-filtered history view.

## Approach

Extend the home screen's merged timeline with a new `_VoiceQueueEntry` type that renders pending voice queue rows inline, sorted by timestamp alongside real entries. When sync processes a row, it disappears automatically via the reactive stream.

## Data Layer

**`local_voice_queue_dao.dart`** — add one method:

```dart
Stream<List<LocalVoiceQueueData>> watchPending() {
  return (select(db.localVoiceQueue)
        ..where((q) => q.syncStatus.equals('pending'))
        ..orderBy([(q) => OrderingTerm.desc(q.loggedAt)]))
      .watch();
}
```

No schema changes required.

## Provider

New file: `lib/core/api/providers/voice_queue_provider.dart`

```dart
class VoiceQueueNotifier extends StreamNotifier<List<LocalVoiceQueueData>> {
  @override
  Stream<List<LocalVoiceQueueData>> build() {
    return ref.watch(localVoiceQueueDaoProvider).watchPending();
  }
}

final voiceQueueProvider =
    StreamNotifierProvider<VoiceQueueNotifier, List<LocalVoiceQueueData>>(
        VoiceQueueNotifier.new);
```

Follows the same pattern as `wellbeingProvider`, `symptomsProvider`, and `mealsProvider`.

## Home Screen Changes

### New sealed subtype

```dart
final class _VoiceQueueEntry extends _TimelineEntry {
  final LocalVoiceQueueData item;
  _VoiceQueueEntry(this.item);
  @override
  DateTime get loggedAt =>
      DateTime.fromMillisecondsSinceEpoch(item.loggedAt);
}
```

### `_HomeScreenState.build()`

Watch `voiceQueueProvider` alongside the existing three providers. Pass the list into `_TimelineBody`.

### `_TimelineBody`

Accept `List<LocalVoiceQueueData> voiceQueue`. Add to the merged entries list:

```dart
for (final q in voiceQueue) _VoiceQueueEntry(q),
```

Existing sort (descending by `loggedAt`) handles placement automatically.

### `_buildEntry`

Add a branch for `_VoiceQueueEntry` → renders `_VoiceQueueCard`.

## UI — `_VoiceQueueCard`

| Element | Detail |
|---|---|
| Leading icon | `Icons.mic` (or `Icons.hourglass_top`) |
| Title | Raw transcript text |
| Subtitle | Formatted logged time |
| Trailing | `IconButton(icon: Icons.help_outline)` |
| Card tap | No-op |

Tapping the `?` icon opens an `AlertDialog`:

> **"Voice note queued"**
>
> *"Hearty couldn't reach the server when you recorded this. It'll be processed and appear here as a proper log entry once you reconnect."*

Visual treatment: slightly muted/dimmed compared to synced entries to signal pending state (e.g. reduced opacity or `onSurfaceVariant` text colour).

## Data Flow

1. User dictates while offline → `local_voice_queue_dao.insertPending()` → `syncStatus = 'pending'`
2. `voiceQueueProvider` stream emits → `_VoiceQueueCard` appears in timeline
3. Connectivity restored → sync runs → `_pushVoiceQueue()` replays transcript through `/api/chat`
4. `local_voice_queue_dao.markDone(id)` sets `syncStatus = 'done'` → stream emits → card disappears
5. Next pull brings real entry from server → real card appears in its place

## Out of Scope

- History screen visibility (pending items have no type classification yet)
- Failed queue entry UI (separate concern — already handled by the failed sync banner)
- Editing or deleting a queued entry
