# Hearty — Phase 2: Android App Specification

**Document:** `hearty-04-android-app.md`
**Date:** 2026-05-04
**Phase:** 2 of 4
**Status:** Draft

---

## 1. Overview

### Purpose

Phase 2 delivers the primary user-facing product: a Flutter Android application that makes food and symptom logging feel effortless. The app is the day-to-day interface for Hearty. It consumes the backend built in Phase 1 (Supabase database, FastAPI REST API, Node.js MCP Server) and adds voice-first interaction, photo capture, offline resilience, and push notifications on top.

### Scope

Phase 2 covers everything from the Flutter project scaffold to a shippable Android APK. Specifically:

- Flutter project structure and architecture
- Wake word detection via Porcupine foreground service
- Voice capture (speech-to-text) and voice response (text-to-speech)
- Meal, symptom, and wellbeing logging flows
- Photo capture with categorization (food plate, barcode, nutrition label, food label)
- Offline queue with background sync
- Push notification system (FCM + local)
- Google OAuth authentication via Supabase Auth
- Navigation and all key screens
- Integration wiring to Phase 1 services

iOS support is explicitly out of scope for Phase 2. The Flutter codebase is written to support iOS in a future phase with minimal rework; no iOS-specific features or testing are required now.

### What Phase 2 Delivers

At the end of Phase 2, the owner can:

1. Speak to their Android phone (or use the wake word) and log a meal or symptom in under 15 seconds.
2. Snap a photo of food, a barcode, or a nutrition label and have it processed into a structured log entry.
3. Receive a gentle notification ~45 minutes after logging a meal, prompting a wellbeing check-in.
4. Use the app fully offline; logs queue locally and sync automatically when connectivity restores.
5. View a timeline of past logs and basic trend visualizations.
6. Configure their health profile (allergens, conditions, dietary protocols) and notification preferences.

---

## 2. Flutter Project Structure

The app lives in a directory named `hearty_app/` at the repository root. The structure follows feature-first architecture under `lib/features/`, with shared cross-cutting concerns under `lib/core/`.

```
hearty_app/
  lib/
    main.dart
    app/
      router.dart         — GoRouter navigation
      theme.dart          — Material 3 theming
    features/
      wake_word/          — wake word detection service
      voice/              — voice capture + TTS
      logging/            — meal/symptom/wellbeing logging flows
      history/            — view past logs
      trends/             — basic trend visualization (charts)
      health_profile/     — allergens, conditions, protocols
      settings/           — notification prefs, auth, etc.
      photos/             — camera capture + categorization
    core/
      api/                — REST API client (Dio)
      offline/            — SQLite queue (drift/sqflite)
      auth/               — Supabase Auth + Google OAuth
      notifications/      — FCM + local notifications
      sync/               — background sync service
```

### Architectural Notes

**State management:** Riverpod throughout. Each feature folder contains its own providers. Avoid global mutable state outside of providers.

**Routing:** GoRouter with `ShellRoute` for the bottom navigation shell. Deep links from notifications use named routes.

**Dependency injection:** Riverpod's `Provider`/`ProviderScope` handles DI. No `get_it` or `injectable`.

**Feature folder anatomy:** Each feature folder contains at minimum:
- `screens/` — full-page `Widget` classes
- `widgets/` — reusable sub-widgets scoped to the feature
- `providers/` — Riverpod providers (state, notifiers, async)
- `models/` — local data models (may mirror API response shapes)

**Platform channels:** Wake word detection requires platform channel calls to Kotlin code. These live in `android/app/src/main/kotlin/com/hearty/app/`.

---

## 3. Wake Word Detection

### Pre-Phase 2 Setup: Porcupine Wake Word Model

> Before wake word development can begin, the following steps must be completed manually:
>
> 1. Create a free account at [console.picovoice.ai](https://console.picovoice.ai)
> 2. Navigate to **Porcupine Wake Word** and create a new wake word: **"Hey Hearty"**
> 3. Select **Android** as the platform, download the generated `.ppn` model file
> 4. Place the file at `hearty_app/assets/wake_word/hey_hearty_android.ppn`
> 5. Register the asset in `pubspec.yaml` under `flutter: assets:`
>
> This is a one-time setup. The `.ppn` file is committed to the repo (it is not a secret).

### 3.1 Wake Word Detection: Picovoice Porcupine

**Library:** `porcupine_flutter` (Picovoice's official Flutter package).

**Why Porcupine:**
- On-device inference — no network call required for wake word detection.
- Works while the screen is off (via foreground service).
- Free tier includes one custom wake word or use of built-in keywords.
- Minimal battery impact (~1-2% per hour on modern hardware).

**Custom wake word:** "Hey Hearty" — commissioned via Picovoice Console (free for personal use). The `.ppn` model file ships bundled in `assets/wake_word/hey_hearty_android.ppn`.

**Fallback:** If the user has not configured the wake word service or denies microphone permission, they tap the floating action button on the home screen to activate listening.

### 3.2 Always-On Background Service

Wake word detection runs in a persistent foreground `Service` (`HeartyWakeWordService.kt`) so it continues when the app is backgrounded or the screen is off.

The foreground service displays a persistent notification (required by Android for foreground services):

- **Small icon:** Hearty heart icon
- **Text:** "Hearty is listening for 'Hey Hearty'"
- **Action button:** "Pause listening" (disables wake word detection until tapped again)

The service is started on boot via `BOOT_COMPLETED` receiver and restarts itself if killed by the OS.

Flutter communicates with the Kotlin service via a `MethodChannel` named `com.hearty.app/wake_word`. The channel carries three events: `wakeWordDetected`, `startListening`, `stopListening`.

### 3.3 Activation Flow

```
1. Wake word detected (or FAB tapped)
   ↓
2. App opens overlay (translucent full-screen or bottom sheet)
   — animated waveform / pulse indicator shows "listening" state
   ↓
3. Android SpeechRecognizer begins capturing audio
   ↓
4. User speaks (e.g., "I just had a burger and fries for lunch")
   ↓
5. Transcription returned as text
   ↓
6. Text sent to Claude API via FastAPI /api/chat with Hearty system context
   ↓
7. Claude determines: health-related query? YES → proceed; NO → redirect
   ↓
8. If health-related: Claude extracts structure, calls log_meal / log_symptoms
   Response text sent to TTS → spoken aloud
   ↓
9. App asks optional follow-up: "How are you feeling?"
   — waits for user response or 3-second silence to dismiss
   ↓
10. Overlay dismisses
```

### 3.4 Non-Health Query Handling

Claude includes a system-level instruction to classify every incoming query as health-related or not. If not health-related, Claude responds with a fixed template:

> "For that, try asking [configured assistant]."

The configured assistant is set in the Settings screen (default: Google Assistant). The app dismisses the overlay after speaking this response. Hearty does not attempt to answer general queries, search the web, set timers, or perform any non-health actions — this keeps the AI context clean and prevents scope creep in the system prompt.

---

## 4. Voice I/O

### 4.1 Speech-to-Text

**Method:** Android's built-in `SpeechRecognizer` API, accessed via Flutter's `speech_to_text` package.

**Why built-in STT:**
- Zero incremental cost.
- Works well for the short, structured utterances typical of meal logging.
- No dependency on a third-party speech API key.
- Supports continuous listening mode for longer symptom descriptions.

**Behavior:**
- Starts listening immediately when the overlay opens.
- Shows a live waveform animation while audio is being captured.
- Auto-stops after 2 seconds of silence (configurable in Settings: 1–5 seconds).
- Displays transcribed text in real-time as partial results arrive.
- User can tap a "Retry" button if the transcription is obviously wrong before sending.

**Language:** Defaults to the device locale. Falls back to `en-US` if locale is unsupported.

### 4.2 Text-to-Speech

**Package:** `flutter_tts`

**Voice selection:** Uses the Android system TTS engine (Google TTS by default). Speech rate set to 0.9 (slightly slower than default for clarity). Pitch set to 1.0. Both are user-configurable.

**Behavior:**
- Speaks Claude's response immediately after it arrives (streaming is not used — wait for the full response then speak, to avoid mid-sentence interruptions).
- Displays the spoken text on screen simultaneously (for users in noisy environments or who prefer to read).
- Can be interrupted by tapping the screen — stops TTS and re-opens listening state.

### 4.3 Conversation Flow

A typical voice logging session follows this pattern:

```
[Overlay opens]
App: (listening state — no prompt, just waveform)

User: "I just had a large wintergreen melon drink from Gong Cha"

App transcribes, sends to Claude with Hearty context:
  - System prompt: Hearty persona + user's health profile
  - Prior session context: last 3 log entries (for continuity)

Claude responds:
  "Logged! I couldn't find exact nutritional info for that — I'll note it
   as a specialty drink. How are you feeling?"

App speaks response via TTS.

[Listening re-opens for follow-up]

User: "Pretty good, a little full"

Claude responds:
  "Got it — logged a wellbeing check-in: mild fullness noted. I'll
   follow up in about 45 minutes."

[Overlay dismisses after 3 seconds of silence]
```

### 4.4 Non-Voice Input Fallback

The voice overlay always displays a text field at the bottom. If the user prefers to type (noisy environment, public space, etc.), they tap the text field and type normally. The same Claude processing pipeline handles text input.

### 4.5 Wake Word Activation Feedback

Immediate feedback fires as soon as the wake word is detected — before the Claude API call begins — so the user knows the app heard them during the 3–8 second round trip.

**Audio cue:** A short chime (bundled as an asset at `assets/audio/wake_chime.mp3`) plays the moment the wake word is detected. Played via `AudioPlayer` (just_audio package or similar); does not use TTS. Volume respects system media volume.

**Visual feedback:**
- The voice overlay opens immediately, showing an **animated waveform or pulsing mic icon** in "listening" state.
- Once the user's utterance ends and the audio is sent to Claude, the animation transitions to a subtle **"thinking..." animation** (e.g., three-dot pulse or spinner) to indicate the API call is in progress.
- The visual overlay remains visible and responsive throughout the entire API round trip — the user is never left staring at a blank screen.

**Sequence:**
```
Wake word detected
  → Audio chime plays immediately
  → Overlay opens with waveform animation ("listening")
  → User speaks
  → STT transcription returned
  → Animation transitions to "thinking..." state
  → Claude API call in progress (3–8 seconds)
  → Response received
  → TTS speaks response; overlay shows spoken text
```

---

## 5. Photo Capture Flow

### 5.1 Packages

- **Camera capture:** `camera` Flutter package (full camera control, flash, zoom)
- **Barcode scanning:** `mobile_scanner` Flutter package (real-time ML Kit scanning overlay)

### 5.2 Photo Types

The app handles four distinct photo types, each routed to a different processing backend:

| Type | Detection Method | Backend |
|---|---|---|
| Food Plate | Vision AI (Claude vision) | POST /api/photos/analyze |
| Barcode | `mobile_scanner` real-time scan | POST /api/photos/barcode |
| Nutrition Label | OCR (ML Kit on-device) | POST /api/photos/nutrition-label |
| Food Label / Packaging | OCR (ML Kit on-device) | POST /api/photos/food-label |

### 5.3 Capture Flow

```
1. User taps camera button (home screen FAB or log entry screen)
   ↓
2. Camera screen opens (full-screen viewfinder)
   — Two modes:
     a. Photo mode: tap shutter to capture still image
     b. Barcode mode: real-time scanning overlay (auto-detects and captures barcode)
   ↓
3. Image captured
   ↓
4. Type selector appears (bottom sheet):
     "What did you photograph?"
     [Food / Meal]  [Barcode]  [Nutrition Label]  [Food Label / Package]
   — If user came from barcode mode and a barcode was detected, skip selector
     and pre-select "Barcode"
   — App may also auto-suggest: e.g., if ML Kit recognizes a barcode pattern
     in a still photo, prompt "This looks like a barcode — is that right?"
   ↓
5. Image + type uploaded to FastAPI via multipart POST
   ↓
6. Processing status shown:
     — Spinner with label: "Analyzing food..." / "Looking up barcode..." / "Reading label..."
   ↓
7. Results returned:
     — Food photo: identified foods with estimated quantities, suggest meal type
     — Barcode: product name, brand, full nutritional data from food database
     — Nutrition label: structured macro/micro nutrient data
     — Food label: ingredients list, allergen warnings flagged against health profile
   ↓
8. Results displayed on meal log entry screen for review and confirmation
   — User can edit any field before saving
   — "Looks good → Save" confirms the log entry
```

### 5.4 Allergen Flagging

When a food label or nutrition label is processed, the API cross-references identified allergens against the user's health profile. If a match is found, the app displays a prominent warning:

> "⚠ Contains dairy — flagged as an allergen in your health profile."

This is a display-only warning. The app does not block the user from logging or consuming the food.

---

## 6. Offline Support

### 6.1 Local Storage: Drift

All pending log operations are stored in a local SQLite database using the `drift` package (formerly Moor). Drift provides compile-time SQL verification and a clean Dart API.

**Offline queue table schema:**

```dart
class OfflineQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get actionType => text()(); // 'log_meal' | 'log_symptom' | 'log_wellbeing'
  TextColumn get payload => text()();    // JSON-encoded request body
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  // status: 'pending' | 'syncing' | 'failed'
}
```

### 6.2 Online-First with Offline Fallback

The app always attempts to call the REST API first. If the call fails (no connectivity, timeout, 5xx error), the operation is written to the offline queue. This is handled transparently in the API client layer (`core/api/`) — the calling feature code does not need to know whether an operation was saved locally or remotely.

### 6.3 Background Sync

**Package:** `connectivity_plus` for connectivity monitoring.

The sync service (`core/sync/sync_service.dart`) subscribes to connectivity changes. When connectivity is restored after an offline period, it:

1. Reads all `pending` rows from `OfflineQueue`, ordered by `created_at` ascending.
2. Replays each operation against the REST API in order.
3. On success: deletes the row from the queue.
4. On failure (non-5xx, e.g., validation error): marks the row `failed` and surfaces a notification to the user.
5. On 5xx: increments `retry_count`, leaves as `pending`, retries on next connectivity event (up to 5 retries before marking `failed`).

**Background execution:** `WorkManager` (via `workmanager` Flutter package) schedules a sync task that also runs periodically in the background (every 15 minutes when the device is online), ensuring data syncs even if the user does not actively open the app.

### 6.4 UI Indicators

- **"Offline" badge:** A small amber chip in the app bar when the device has no connectivity. Tapping it shows "X items queued for sync."
- **"Syncing..." indicator:** A brief progress indicator (linear progress bar at top of screen) while the sync is in progress.
- **Sync error:** If any queued items have `status = 'failed'`, a persistent banner appears: "Some logs couldn't sync — tap to review."

---

## 7. Notification System

### 7.1 Architecture: Two Notification Paths

| Path | Package | Use Case |
|---|---|---|
| FCM (Firebase Cloud Messaging) | `firebase_messaging` | Server-triggered: post-meal follow-up nudges, weekly digest |
| Local notifications | `flutter_local_notifications` | On-device: daily check-in reminders, sync errors |

### 7.2 Post-Meal Follow-Up Nudge (Primary Notification)

This is the core behavioral loop that makes Hearty useful over time.

**Trigger:** When the user logs a meal, the FastAPI backend schedules a follow-up FCM push notification for `meal_logged_at + nudge_delay_minutes` (default: 45 minutes, user-configurable from 30–90 minutes).

**Notification content:**
- **Title:** "How are you feeling?"
- **Body:** "You had [meal description] about [X] minutes ago. Any symptoms to log?"
- **Action buttons:** "Log symptoms" (opens voice overlay) | "All good" (logs a clean wellbeing entry) | "Snooze 15 min"

**Single notification per meal:** Only one follow-up notification fires per meal log entry. If the user has already logged a symptom or wellbeing snapshot in the window between meal logging and the notification, the backend cancels the scheduled FCM send.

### 7.3 Daily Check-In

A local notification fires each morning at a user-configured time (default: 8:00 AM).

**Content:**
- **Title:** "Good morning — how did you sleep?"
- **Body:** "Tap to log your morning wellbeing."

Enabled by default. User can disable or change the time in Settings → Notifications.

### 7.4 Weekly Digest

A FCM notification fires every Sunday morning summarizing the past week. Content generated by the API's trend engine:

- **Title:** "Your week in Hearty"
- **Body:** "You logged X meals and Y symptoms. [Top pattern if any]."

Enabled by default. User can disable in Settings → Notifications.

### 7.5 Notification Preferences Screen

Located at Settings → Notifications. Controls:

- Post-meal nudge: toggle on/off; delay slider (30–90 min, 5-min increments)
- Daily check-in: toggle on/off; time picker
- Weekly digest: toggle on/off
- Sync error alerts: toggle on/off (default: on, not recommended to disable)
- **Wake word detection:** toggle on/off (default: **on**). When disabled, the `HeartyWakeWordService` foreground service stops and the persistent "Hearty is listening" notification disappears. The floating action button on the home screen remains available as the primary activation method when wake word is off.

All preferences are stored in Supabase (`user_preferences` table) so they sync across devices, and also cached locally for offline access.

### 7.6 Android Notification Channels

Three notification channels registered at app startup:

| Channel ID | Name | Importance |
|---|---|---|
| `hearty_meal_followup` | Meal Follow-Ups | HIGH (shows heads-up) |
| `hearty_daily_checkin` | Daily Check-In | DEFAULT |
| `hearty_digest` | Weekly Digest | DEFAULT |
| `hearty_system` | Sync & System | LOW |

---

## 8. Auth Flow

### 8.1 Package

`supabase_flutter` + `google_sign_in`

### 8.2 Flow

```
1. App launches
   ↓
2. Splash screen (Hearty logo, 1–2 seconds)
   — Check: is there a valid Supabase session in local storage?
     YES → Skip to Home
     NO  → Continue to sign-in
   ↓
3. Sign-In screen
   — Single button: "Continue with Google"
   — `google_sign_in` triggers native Google OAuth picker
   — ID token passed to `supabase.auth.signInWithIdToken()`
   — Supabase returns session (access token + refresh token)
   ↓
4. First-time user check:
   — Query `user_profiles` table for the authenticated user ID
   — NOT FOUND → Onboarding flow
   — FOUND → Home screen
   ↓
5. Onboarding (first-time only, skippable):
   Screen 1: "Tell us about your health profile"
     — Known allergens (multi-select chip input)
     — Diagnosed conditions (free text, e.g., "IBS", "Crohn's")
     — Dietary protocols (multi-select: Gluten-Free, Dairy-Free, Low-FODMAP, etc.)
   Screen 2: "Set up notifications"
     — Post-meal nudge toggle + delay slider
     — Daily check-in toggle + time picker
   Screen 3 (shown after microphone permission is granted): "Background wake word"
     — Explanation: "Hearty listens for 'Hey Hearty' in the background. This uses
       a small foreground service (~1-2% battery/hour). For reliable wake word
       detection, tap below to exempt Hearty from battery optimization."
     — Button: "Exempt from battery optimization" — deep-links to
       `Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` for the app package
     — "Skip" link available; wake word detection still works without the exemption
       but may be paused by the OS in aggressive battery-saver modes
   "Skip for now" button on each screen — saves what's been filled in
   "Finish" → Home screen
```

### 8.3 Session Management

- Supabase JWT is refreshed automatically by `supabase_flutter`.
- On 401 responses from the FastAPI, the Dio interceptor in `core/api/` triggers a token refresh and retries the request once.
- If refresh fails (token revoked, user signed out on another device), the user is redirected to the Sign-In screen. Local data in the offline queue is preserved and resyncs after re-authentication.

### 8.4 Sign Out

Settings → Account → Sign Out. Clears Supabase session, clears Google sign-in cache. Local SQLite data is preserved (user's own data, not cleared) so re-login immediately restores the offline queue.

---

## 9. Navigation & Key Screens

### 9.1 Navigation Structure

GoRouter with a `ShellRoute` wrapping the main bottom navigation shell. Four tabs:

| Tab | Icon | Route |
|---|---|---|
| Home | home | `/home` |
| History | history | `/history` |
| Trends | show_chart | `/trends` |
| Settings | settings | `/settings` |

Full-screen routes (no tab bar):
- `/log` — Log entry screen (voice/text/photo)
- `/health-profile` — Health Profile editor
- `/log/:id` — Log entry detail view
- `/onboarding` — First-time setup

### 9.2 Home Screen

The primary daily-use screen.

**Sections:**

1. **Today's timeline** (scrollable, newest first)
   - Meal cards: meal type icon + description + timestamp
   - Symptom entries linked to meals (indented under the meal card)
   - Wellbeing snapshot cards (energy, mood shown as small colored chips)

2. **Quick Log FAB (Floating Action Button)**
   - Bottom-right, prominent
   - Tap: opens log entry overlay
   - Long-press or swipe: shows three sub-actions: Voice, Text, Camera

3. **Wellbeing snapshot card** (top of screen, above timeline)
   - Shows today's average energy and mood if a check-in has been logged
   - If no check-in: "Log your morning wellbeing" prompt card

4. **Connectivity / sync status** (app bar trailing widget, shown only when offline or syncing)

### 9.3 Log Entry Screen

The core logging surface. Accessible via FAB or notification tap.

**Layout:**
- Large voice button (circular, pulsing animation when active) — center of screen
- Text input field below the voice button (always visible, tap to focus)
- Camera button — bottom right corner
- "Recent" chips below text field: tappable suggestions based on recent meals (e.g., "Coffee", "Oatmeal")

**Flow:**
1. User activates voice or types.
2. Claude processes input, extracts structure.
3. A review card appears showing what will be logged:
   - Meal: "Burger and fries — lunch"
   - Foods: ["burger", "fries"]
   - Suggested follow-up time: "I'll check in at 2:45 PM"
4. User taps "Log it" or edits any field.
5. Entry saved (or queued offline). Screen dismisses.

### 9.4 History Screen

**Layout:**
- Date-grouped scrollable timeline
- Search bar at top (keyword search across meal descriptions)
- Filter chips: Meals | Symptoms | Wellbeing | All
- Each entry shows: icon, description, timestamp, severity badge (for symptoms)

**Tap behavior:** Opens a detail view (`/log/:id`) showing the full log entry, linked symptoms, and Claude's analysis note (if any).

### 9.5 Trends Screen

Basic visualizations powered by `fl_chart`.

**Charts included:**

1. **Symptom frequency over time** — Line chart, past 30 days, per symptom type
2. **Top trigger foods** — Horizontal bar chart, ranked by `food_triggers.confidence_score`
3. **Energy & mood trends** — Dual-line chart from `wellbeing_snapshots`
4. **Meal type distribution** — Pie or donut chart (breakfast/lunch/dinner/snack breakdown)

**Data source:** All chart data fetched from the FastAPI `/api/trends` endpoint. Charts show a loading skeleton while data is fetching.

**Date range selector:** Defaults to past 30 days. Chip row: "7 days | 30 days | 90 days | All time".

### 9.6 Health Profile Screen

Accessible from Settings tab → Health Profile, or during onboarding.

**Sections:**

1. **Allergens** — Multi-select chip list: Gluten, Dairy, Eggs, Nuts, Soy, Shellfish, Fish, + free-text "Add custom"
2. **Known conditions** — Free-text field with tag-style input (e.g., "IBS", "Acid Reflux")
3. **Dietary protocols** — Multi-select: Gluten-Free, Dairy-Free, Low-FODMAP, Vegetarian, Vegan, Keto, + custom
4. **Medications / Supplements** — Optional list of current medications (helps AI note interactions)

All changes sync immediately to Supabase. The health profile is embedded in the Claude system prompt for every request.

### 9.7 Settings Screen

**Sections:**

- **Account:** Signed in as [email] · Sign Out
- **Health Profile** → navigates to Health Profile screen
- **Notifications** → navigates to Notification Preferences screen
- **Default Assistant** — picker: Google Assistant | Gemini | Siri | None (for non-health redirect)
- **Voice Settings** — TTS speech rate slider, TTS pitch slider, STT silence threshold
- **Data Export** — "Export my data" button (opens format picker: JSON / CSV; sends download via API)
- **About** — version, privacy policy link, open source licenses

---

## 10. Key Flutter Packages

| Package | Purpose |
|---|---|
| `flutter_tts` | On-device text-to-speech for Claude responses |
| `speech_to_text` | Android SpeechRecognizer API wrapper for STT |
| `camera` | Full-featured camera capture for food/label photos |
| `mobile_scanner` | Real-time barcode/QR scanning overlay using ML Kit |
| `drift` | Type-safe SQLite ORM for offline queue and local caching |
| `dio` | HTTP client for FastAPI REST calls; supports interceptors for auth |
| `supabase_flutter` | Supabase client: auth, realtime, direct DB queries |
| `google_sign_in` | Native Google OAuth flow |
| `flutter_local_notifications` | On-device scheduled and immediate notifications |
| `firebase_messaging` | FCM push notification receiver |
| `connectivity_plus` | Network connectivity stream for offline detection |
| `go_router` | Declarative routing with deep link support |
| `fl_chart` | Trend charts: line, bar, pie (Flutter-native, no WebView) |
| `riverpod` (+ `hooks_riverpod`) | State management and dependency injection |
| `porcupine_flutter` | Picovoice Porcupine on-device wake word detection |
| `workmanager` | Background task scheduling for sync jobs |
| `permission_handler` | Runtime permission requests (microphone, camera, notifications) |
| `image_picker` | Gallery access fallback for photo upload |
| `cached_network_image` | Image caching for meal photo thumbnails |

**Minimum SDK:** Android 8.0 (API 26). Targets Android 14 (API 34).

---

## 11. Integration Points

### 11.1 FastAPI REST API (Phase 1)

**Client location:** `lib/core/api/hearty_api_client.dart`

**HTTP client:** Dio with two interceptors:
1. `AuthInterceptor` — injects `Authorization: Bearer {supabase_access_token}` on every request
2. `RetryInterceptor` — on 401, refreshes the Supabase token and retries once; on network failure, throws `OfflineException` (caught by the offline queue handler)

**Base URL:** Configured via `--dart-define=API_BASE_URL=https://...` at build time. Falls through to a local dev URL in debug builds.

**Key endpoints used:**

| Feature | Method | Endpoint |
|---|---|---|
| Log meal (voice/text) | POST | `/api/meals` |
| Log symptom | POST | `/api/symptoms` |
| Log wellbeing | POST | `/api/wellbeing` |
| Chat with Claude (voice AI) | POST | `/api/chat` |
| Upload photo | POST | `/api/photos/analyze` |
| Scan barcode | POST | `/api/photos/barcode` |
| Fetch history | GET | `/api/meals?start=&end=&limit=` |
| Fetch trends | GET | `/api/trends` |
| Get user preferences | GET | `/api/preferences` |
| Save user preferences | PUT | `/api/preferences` |
| Export data | GET | `/api/export/json` |

**Offline queue integration:** When the `RetryInterceptor` catches an `OfflineException`, it writes the request payload to the Drift `OfflineQueue` table. The sync service replays these on connectivity restore.

### 11.2 Supabase Auth

**Package:** `supabase_flutter`

**Initialization:** Called in `main.dart` before `runApp()`:

```dart
await Supabase.initialize(
  url: const String.fromEnvironment('SUPABASE_URL'),
  anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);
```

**Session persistence:** `supabase_flutter` handles token storage in secure local storage automatically.

**Auth state stream:** `Supabase.instance.client.auth.onAuthStateChange` drives the GoRouter redirect logic — unauthenticated state redirects to `/sign-in`.

**Direct Supabase queries:** The app does not query Supabase tables directly from the Flutter client except for auth state. All data operations go through the FastAPI REST API to enforce server-side business logic and keep RLS as a defense-in-depth layer, not the primary access control.

### 11.3 FCM (Firebase Cloud Messaging)

**Package:** `firebase_messaging`

**Setup:**
1. Firebase project linked to the Android app (`google-services.json` in `android/app/`).
2. FCM token retrieved on app launch and sent to the FastAPI via `PUT /api/preferences` along with other device metadata.
3. The FastAPI stores the FCM token in `user_preferences.fcm_token` and uses it to send server-side push notifications (post-meal nudges, weekly digest).

**Foreground handling:** When a notification arrives while the app is open, `firebase_messaging`'s `onMessage` stream handles it — displayed as a local notification (not relying on the system notification drawer).

**Background/terminated handling:** `firebase_messaging`'s background message handler routes notification taps to the correct GoRouter deep link (`/log` for "Log symptoms" action, `/home` for "All good" action).

### 11.4 Picovoice Porcupine (Wake Word)

**Package:** `porcupine_flutter`

**Platform:** The Flutter package wraps the native Android SDK. The Porcupine engine runs in the `HeartyWakeWordService` Kotlin foreground service, not directly in the Flutter Dart isolate. Communication is via `MethodChannel('com.hearty.app/wake_word')`.

**Access key:** Picovoice access key stored as a build-time `--dart-define` variable (`PICOVOICE_ACCESS_KEY`). The free tier allows one wake word and development/personal use without payment.

**Wake word model file:** `assets/wake_word/hey_hearty_android.ppn` — bundled in the app, no network call required at runtime.

**Sensitivity:** Default 0.5 (range 0.0–1.0). Higher values increase detection rate but also false positives. User-configurable in Settings → Voice Settings.

**Lifecycle:**
- Service starts on `BOOT_COMPLETED` and when the app is first launched.
- Service binds to the Flutter engine for MethodChannel communication.
- When a wake word is detected, the service calls `wakeWordDetected` on the MethodChannel, which triggers the activation flow in Flutter.
- Service pauses detection while the microphone is in use for STT (to avoid conflicts).

---

## Appendix: Android Manifest Permissions Summary

```xml
<!-- Microphone for wake word and STT -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />

<!-- Foreground service for always-on wake word detection -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />

<!-- Camera for photo capture -->
<uses-permission android:name="android.permission.CAMERA" />

<!-- Network -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- Boot receiver for wake word service restart -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<!-- Notifications (Android 13+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Vibration for notification feedback -->
<uses-permission android:name="android.permission.VIBRATE" />
```

---

## Appendix: Environment Variables

| Variable | Where Set | Description |
|---|---|---|
| `API_BASE_URL` | `--dart-define` at build | FastAPI base URL |
| `SUPABASE_URL` | `--dart-define` at build | Supabase project URL |
| `SUPABASE_ANON_KEY` | `--dart-define` at build | Supabase anon key (public) |
| `PICOVOICE_ACCESS_KEY` | `--dart-define` at build | Picovoice console access key |
| `FIREBASE_ENABLED` | `--dart-define` at build | `true`/`false`, disables FCM in dev |

All `--dart-define` values are injected at CI build time from GitHub Actions secrets. They are not stored in source control.

---

*End of Phase 2: Android App Specification*
