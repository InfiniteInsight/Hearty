# Offline-First Local Cache

**Date:** 2026-05-14
**Status:** Implemented (schema v3)

## Problem

All data providers fetch directly from the API with no local fallback. When the API is unreachable (dev server down, no connectivity, outage), every screen renders empty or errors. Worse, data logged while offline is only held in provider memory — a restart loses it. Users need confidence that what they log is remembered, and that screens always show the last known state.

## Goal

The app functions fully offline. Data logged without connectivity is immediately visible in the UI and persists until synced to the server. Screens never fail due to API unavailability — they show cached data instead. The app can tolerate being offline for multiple days.

## Out of Scope

- **Photos** — real-time upload, no meaningful offline behavior; gracefully unavailable when offline
- **History beyond 7 days** — synced records older than 7 days are pruned from local storage

## Partially In Scope: Voice

Voice is a real-time session and cannot be fully offline. However, the meal log that the chat endpoint creates on the server is now recoverable when offline:

- **Online:** voice transcript → `POST /api/chat` → server logs the meal → sync pulls it into local DB → UI updates
- **Offline:** transcript saved to `local_voice_queue` → user hears *"You're offline, but I saved that. I'll log it when you reconnect."* → on next sync, each queued transcript is replayed through `/api/chat` with the original `logged_at` timestamp → meal appears in UI

The original timestamp is preserved: `local_voice_queue` stores `logged_at` in unix ms, and the sync service passes it to the chat API as `logged_at` in the request body. The server uses it when inserting the meal row.

---

## Architecture: Local-First with Background Sync

The local Drift database becomes the source of truth. Providers read from local tables only. The API is a sync target, not a source. A sync service pushes pending local records to the API and pulls server data back when connectivity is available.

```
User Action → Provider → Local Drift Table → UI (immediate, always)
                                  ↕
                           Sync Service (background)
                                  ↕
                              API / Server
```

---

## Section 1: Local Database Schema

The existing `offline_queue` table is retired and replaced by proper entity tables in `lib/core/offline/offline_database.dart`. Any records pending in `offline_queue` at migration time are dropped — acceptable since this ships as a new feature, not an upgrade with guaranteed data continuity.

### `local_meals`
| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | Local UUID — never changes, used by UI |
| `server_id` | TEXT? | Populated after successful sync |
| `description` | TEXT | |
| `meal_type` | TEXT | |
| `foods` | TEXT | JSON array |
| `logged_at` | INTEGER | Unix ms |
| `claude_note` | TEXT? | |
| `sync_status` | TEXT | `pending` \| `synced` \| `failed` |

### `local_symptoms`
| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | Local UUID |
| `server_id` | TEXT? | |
| `description` | TEXT | |
| `severity` | INTEGER | 1–5 |
| `linked_meal_id` | TEXT? | References local meal `id` |
| `logged_at` | INTEGER | Unix ms |
| `sync_status` | TEXT | |

### `local_wellbeing`
| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | Local UUID |
| `server_id` | TEXT? | |
| `energy` | INTEGER | |
| `mood` | INTEGER | |
| `notes` | TEXT? | |
| `period` | TEXT? | `morning` \| `midday` \| `evening` |
| `logged_at` | INTEGER | Unix ms |
| `sync_status` | TEXT | |

### `local_preferences`
| Column | Type | Notes |
|--------|------|-------|
| `id` | INTEGER PK | Always row 1 |
| `data` | TEXT | JSON blob of `UserPreferences` |
| `sync_status` | TEXT | |

### `local_trends_cache`
| Column | Type | Notes |
|--------|------|-------|
| `id` | INTEGER PK | Always row 1 |
| `data` | TEXT | JSON blob of `TrendsData` |
| `cached_at` | INTEGER | Unix ms |

### `local_voice_queue`
| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | Local UUID |
| `transcript` | TEXT | Raw speech-to-text string |
| `logged_at` | INTEGER | Unix ms — time the user spoke, preserved on replay |
| `sync_status` | TEXT | `pending` \| `failed` (no `synced` — done rows are deleted) |

### Key Design Decisions

- **Local UUIDs are stable** — the UI always uses the local `id`. The `server_id` is populated silently after sync. No ID churn in provider state.
- **`server_id` determines sync action** — `null` → POST (create); non-null → PATCH (update). Handles wellbeing edits correctly.
- **Preferences conflict rule** — if local preferences are `pending`, skip the pull for preferences during that sync cycle. Push first, pull on the next cycle.
- **Pruning** — after each sync, delete `synced` records with `logged_at` older than 7 days. Pending records are kept regardless of age.
- **Voice queue entries are deleted on success** — unlike entity tables, `local_voice_queue` rows are hard-deleted by `markDone()` rather than marked `synced`. They don't need to persist after replay because the resulting meal row lives in `local_meals` after the pull phase.

---

## Section 2: Provider Layer

Providers migrate from `AsyncNotifier` (one-shot API fetch) to `StreamNotifier` (reactive Drift watch). Writes go to the local table immediately — the stream fires and the UI updates with no API involvement.

### Pattern (meals, symptoms, wellbeing)

```dart
class MealsNotifier extends StreamNotifier<List<MealLog>> {
  Stream<List<MealLog>> build() {
    return ref.watch(localMealDaoProvider)
        .watchToday()
        .map((rows) => rows.map(MealLog.fromLocal).toList());
  }

  Future<void> logMeal(String description, {String? mealType}) async {
    await ref.read(localMealDaoProvider).insert(
      LocalMeal(id: uuid(), description: description, syncStatus: 'pending', ...),
    );
    ref.read(syncServiceProvider).schedule();
  }
}
```

### Preferences

Stays as `AsyncNotifier`. On `build()`, reads from the local `local_preferences` row. If the row is empty (first install, no prior sync), attempts an API fetch to bootstrap it; if that also fails, returns a `UserPreferences` default. On `save()`, writes locally with `sync_status = 'pending'` and schedules sync. The screen is never blocked by API availability.

### Trends

Stays as `AsyncNotifier`. On `build()`, reads from `local_trends_cache`. Shows `cached_at` timestamp so the user knows how fresh it is. Refreshed by the sync service when online.

### Voice Provider

After a successful `client.chat()` call, `VoiceNotifier.sendToChat()` calls `syncTriggerProvider.schedule()` so the resulting server-side meal is pulled into the local DB immediately, making it appear in the home screen without a restart.

When `OfflineException` is thrown, the transcript is saved to `local_voice_queue` instead and the user receives an offline acknowledgment.

### DAO Layer

One DAO per entity, colocated with the existing offline database:

```
lib/core/offline/
  offline_database.dart         (extended with new tables, offline_queue retired)
  local_meal_dao.dart           (watchToday, insert, markSynced, upsertFromServer, prune)
  local_symptom_dao.dart
  local_wellbeing_dao.dart
  local_preferences_dao.dart    (readRow, writeRow, markSynced)
  local_trends_dao.dart         (readCache, writeCache)
  local_voice_queue_dao.dart    (insertPending, getPending, markDone, markFailed)
  sync_service.dart
```

---

## Section 3: Sync Service

A single Riverpod `Provider<SyncService>` owns the entire push/pull cycle. It is the only place the API is called after this change (except trends manual refresh from the trends screen).

### Triggers

1. App foreground (`AppLifecycleState.resumed`)
2. Connectivity restored — via `connectivity_plus` stream
3. After any local write — provider calls `syncService.schedule()`
4. Periodic — every 5 minutes while app is open

A concurrency guard prevents overlapping sync cycles. If sync is already running when a trigger fires, a `dirty` flag is set so the cycle reruns immediately after finishing.

### Push Phase

```
For each record where sync_status = 'pending' (meals, symptoms, wellbeing, preferences):
  if server_id == null:
    POST /api/[entity]
    on success → server_id = response.id, sync_status = 'synced'
    on 4xx → sync_status = 'failed'
    on network error → leave as pending (retried on next trigger)
  if server_id != null:
    PATCH /api/[entity]/[server_id]
    on success → sync_status = 'synced'
    on 4xx → sync_status = 'failed'
    on network error → leave as pending

For each record in local_voice_queue where sync_status = 'pending':
  POST /api/chat  { message: transcript, logged_at: <original unix ms as ISO 8601 UTC> }
  on success → delete row (markDone)
  on 4xx → sync_status = 'failed'
  on network error → leave as pending

if any records were newly synced:
  signal native layer → enqueueIdleAnalysis (via method channel)
```

### Pull Phase

Runs after push (or immediately if nothing was pending):

```
GET /api/meals, /api/symptoms, /api/wellbeing (today + yesterday window)
  For each server record:
    if local record with matching server_id exists AND sync_status = 'synced' → upsert (server wins)
    if no local record → insert as synced
    (pending local records are never overwritten)

GET /api/preferences (only if local preferences sync_status = 'synced')
  → overwrite local_preferences row

GET /api/trends
  → overwrite local_trends_cache row
```

### Prune Phase

After pull: delete `sync_status = 'synced'` records with `logged_at` older than 7 days.

### New Dependency

`connectivity_plus` — standard Flutter package for connectivity stream.

---

## Section 4: Analysis Worker Interaction

The `AnalysisWorker` (WorkManager) calls `POST /api/trends/analyze` in two modes:

- **Nightly periodic** — registered at app start, runs every 24h, requires network
- **Idle one-shot** — triggered after new data is logged, requires network + device idle

Both modes pre-check `/api/trends/analyze/status` for a `has_new_data` flag and skip if false.

### Change

Remove `_enqueueIdleAnalysis()` from `MealsNotifier` and `WellbeingNotifier`. Move it to the sync service push phase: after any records are successfully pushed to the server, call `enqueueIdleAnalysis`. This guarantees the server has the data before the analysis worker runs.

The nightly periodic job is unaffected — it will find `has_new_data = true` if sync has already occurred, or skip gracefully if not.

### Correct Sequence (Post-Change)

```
connectivity restored
  → sync service pushes pending records
  → server has new data (has_new_data = true)
  → sync service signals enqueueIdleAnalysis
  → WorkManager waits for device idle + network
  → AnalysisWorker checks has_new_data = true → runs analysis
  → sync service (next cycle) pulls updated trends into local_trends_cache
```

### Pre-Existing Issue (Out of Scope)

`AnalysisWorker` accepts `KEY_AUTH_TOKEN` but `MainActivity` currently passes `authToken = null` for both periodic and idle registrations. Analysis requests run unauthenticated. This should be addressed in a separate fix.

---

## Conflict Policy

Server wins for synced records on pull. Pending local records are never overwritten. If both sides have changes (multi-device or reinstall scenario), local pending changes push first; server data is then pulled on the subsequent cycle. The user expects this — if the API was unreachable, they don't expect it to be in sync.
