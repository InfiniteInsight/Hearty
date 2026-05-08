# Hearty — Android App (Spec 04) — Living Plan

**Spec:** [`hearty-04-android-app.md`](../specs/2026-05-04-hearty-04-android-app.md)  
**Roadmap Phase:** Phase 2 — Android App  
**Plan Status:** 🟡 In Progress  
**Last Updated:** 2026-05-08 (Phase 7 complete; Phase 8 next)  
**Last Verified Against Spec:** 2026-05-08  
**Open Deviations:** 1

---

## How to Use This Plan

1. Always start with **Phase 0** at the beginning of any new session on this plan
2. Find the first phase/task marked **🔴 Not Started**, mark it **🟡 In Progress**
3. Paste the phase's **Activation Prompt** into a new Claude Code session
4. Follow the steps — Claude will guide you through each one
5. At natural break points, Claude will tell you to run `/compact`; do so, then start a new session with the **Activation Prompt** at the top of the next phase
6. Mark completed phases **🟢 Completed** and log any deviations as a single line at the bottom

**Status key:** 🔴 Not Started · 🟡 In Progress · 🟢 Completed · ⚠️ Blocked · ↩️ Deviated

---

## Phase Summary

| Phase | Name | Status | Depends On | Type |
|---|---|---|---|---|
| 0 | Review & Align | 🟢 Completed | — | Claude (start of every session) |
| 1 | Flutter Project Setup | 🟢 Completed | — | Claude |
| 2 | UI Shell & Navigation | 🟢 Completed | Phase 1 | Claude |
| 3 | Auth (Google OAuth + Supabase) | 🟢 Completed | Phase 1 | Claude |
| 4 | Voice Input, TTS & Wake Word | 🟢 Completed | Phases 2–3 | Mixed (openWakeWord training + Claude) |
| 5 | Meal, Symptom & Wellbeing Logging | 🟢 Completed | Phases 2–4 | Claude |
| 6 | Offline Queue & Background Sync | 🟢 Completed | Phase 5 | Claude |
| 7 | Camera & Photo Types | 🟢 Completed | Phases 2–3 | Claude |
| 8 | Notification System | 🔴 Not Started | Phases 3, 5 | Mixed |
| 9 | Integration Test | 🔴 Not Started | Phases 1–8 | Claude |

---

## Phase 0: Review & Align

**Status:** 🟢 Completed  
**Goal:** Verify the dev environment, confirm all dependency plans are complete, check the spec hasn't drifted from this plan, and identify exactly which phase to start or resume.  
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty Android App (Spec 04).
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

Working directory: /home/evan/projects/food-journal-assistant

Steps:

1. Read all of these files in full:
   - docs/superpowers/plans/2026-05-04-hearty-04-android-app-plan.md  (this plan)
   - docs/superpowers/specs/2026-05-04-hearty-04-android-app.md

2. Check dependency plan completion — read the Plan Status line from each:
   - docs/superpowers/plans/2026-05-04-hearty-01-database-plan.md
   - docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md
   - docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md
   All three must show Plan Status: 🟢 Completed before Phase 1 can begin.

3. Check the dev environment (run each command):
   - flutter --version   (need Flutter 3.x stable)
   - dart --version      (bundled with Flutter; confirm present)
   - java --version      (need JDK 17+ for Android Gradle)
   - git status
   - ls hearty_app/ 2>/dev/null && echo "project exists" || echo "not yet created"

4. For the first upcoming non-zero phase (Phase 1 if project not yet created), also verify:
   - Android SDK: check that ANDROID_HOME or ANDROID_SDK_ROOT is set
     (run: echo $ANDROID_HOME or printenv | grep ANDROID)
   - Check Picovoice console access: confirm PICOVOICE_ACCESS_KEY is listed in
     the project's environment variable documentation or .env
   - Check Firebase: ls android/app/google-services.json 2>/dev/null || echo "not yet added"

5. Spec drift check — the plan was written on 2026-05-04. Scan the spec for any
   changes to: project structure, key packages, wake word approach, auth flow,
   offline queue schema. If you find anything that conflicts with this plan,
   list it.

6. Report:
   - Dependency plans: which are complete, which are not
   - Environment: what is/isn't installed or configured
   - Spec alignment: any drift found, or "clean"
   - Next action: which phase to proceed with (or what to fix/unblock first)

Before running any command, verify it exists with --help or equivalent.
If a command doesn't behave as expected, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
```

**Deviation Log:** _None_

---

## Phase 1: Flutter Project Setup

**Status:** 🟢 Completed  
**Goal:** Scaffold the `hearty_app/` Flutter project with feature-first directory structure, all pubspec dependencies, and build-time `--dart-define` env configuration.  
**Depends on:** Dependency plans complete (Specs 01, 02, 03 all 🟢)  
**Type:** Claude

**Key deliverables:**
- `hearty_app/` directory created via `flutter create` with package name `com.hearty.app` ✓
- Full feature-first directory structure under `lib/features/` and `lib/core/` matching the spec ✓
- `pubspec.yaml` with all packages from Section 10 of the spec pinned at specified versions ✓
- Android manifest with all required permissions from the spec appendix + `SCHEDULE_EXACT_ALARM` ✓
- `README` in `hearty_app/` documenting the `--dart-define` variables ✓
- `flutter analyze` passes with zero errors ✓

**Deviation Log:** Spec says "pinned at specified versions" but lists no version numbers — used current stable from pub.dev (2026-05-05). Added `SCHEDULE_EXACT_ALARM` permission not in spec appendix (required by `flutter_local_notifications` on Android 12+).

---

## Phase 2: UI Shell & Navigation

**Status:** 🟢 Completed  
**Goal:** Build the GoRouter navigation shell with all four bottom-tab routes, all full-screen route stubs, Material 3 theming, and placeholder screens so every named route renders without crashing.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- `app/router.dart` — GoRouter with `ShellRoute` wrapping the four-tab bottom nav (Home, History, Trends, Settings)
- Full-screen routes stubbed: `/log`, `/health-profile`, `/log/:id`, `/onboarding`
- `app/theme.dart` — Material 3 theme wired up in `main.dart`
- Placeholder screen widgets for every route (shows route name, no crashes)
- Riverpod `ProviderScope` wrapping the app root in `main.dart`

**Deviation Log:** _None_

---

## Phase 3: Auth (Google OAuth + Supabase)

**Status:** 🟢 Completed  
**Goal:** Implement the full auth flow — Supabase initialization, Google Sign-In, session persistence, first-time onboarding screens, and GoRouter redirect logic — so the app correctly routes authenticated and unauthenticated users.  
**Depends on:** Phases 1–2; Spec 01 plan complete (Google OAuth configured in Supabase Dashboard)  
**Type:** Claude

**Key deliverables:**
- `core/auth/` — Supabase initialization in `main.dart`, `AuthInterceptor` for Dio, auth state stream wired to GoRouter redirects
- Sign-In screen with "Continue with Google" button using `google_sign_in` + `supabase_flutter`
- Onboarding flow (3 screens): health profile setup, notification prefs, wake word battery-optimization prompt
- First-time user check against Supabase (`user_profiles` table) — routes to onboarding vs. home
- Sign-Out in Settings clears session and Google sign-in cache; local SQLite data preserved
- Android SHA-1 fingerprint registered in Google Cloud Console and Supabase (if not done in Spec 01 Phase 3)

**Deviation Log:** _None_

---

## Phase 4: Voice Input, TTS & Wake Word

**Status:** 🟢 Completed  
**Goal:** Implement the complete voice I/O loop — STT overlay, TTS response, wake word detection foreground service, and the activation feedback sequence — wired to the log entry screen.  
**Depends on:** Phases 2–3  
**Type:** Mixed (openWakeWord model training + Claude implementation)

**Task plan:** [`2026-05-07-hearty-04-phase4-voice-wake-word.md`](2026-05-07-hearty-04-phase4-voice-wake-word.md)

**Key deliverables:**
- **Pre-phase manual step:** ✅ DONE — `hearty_app/assets/wake_word/hey_hearty.onnx` trained and registered in `pubspec.yaml`
- `HeartyWakeWordService.kt` — Android foreground service using ONNX Runtime for Android (Gradle dep: `com.microsoft.onnxruntime:onnxruntime-android`), with `BOOT_COMPLETED` receiver, persistent notification with "Pause listening" action, `MethodChannel('com.hearty.app/wake_word')`
- `features/voice/` — STT via `speech_to_text`, live waveform animation, auto-stop on 2s silence, retry button
- `features/voice/` — TTS via `flutter_tts` at 0.9 speech rate; interruptible by screen tap
- Wake chime (`assets/audio/wake_chime.mp3`) played immediately on wake word detection via `just_audio`
- Full activation flow: wake → chime → overlay (listening) → STT → thinking animation → Claude API → TTS response → optional follow-up → dismiss
- Non-health query redirect to configured assistant (Settings → Default Assistant)

**Model I/O (confirmed 2026-05-07):** `hey_hearty.onnx` — input `x` [1, 16, 96] float32; output `sigmoid` [1, 1] float32

**Deviation Log:** 2026-05-06 — Switched from Picovoice Porcupine to openWakeWord (open source, ONNX-based). Removed `porcupine_flutter` from pubspec.yaml; ONNX Runtime for Android added as a Gradle dependency instead. No API key required. Asset path changed from `.ppn` to `.onnx`.

---

## Phase 5: Meal, Symptom & Wellbeing Logging

**Status:** 🟢 Completed  
**Goal:** Implement all three logging flows (meal, symptom, wellbeing) wired to the FastAPI REST API, including the Log Entry screen, Home screen timeline, History screen, Trends charts, and Health Profile editor.  
**Depends on:** Phases 2–4  
**Type:** Claude

**Key deliverables:**
- Log Entry screen: voice button, text field, camera button, recent-meal chips, review card with "Log it" confirmation
- Home screen: today's timeline (meal/symptom/wellbeing cards), wellbeing snapshot card, Quick Log FAB with voice/text/camera sub-actions
- History screen: date-grouped timeline, keyword search, filter chips (Meals/Symptoms/Wellbeing/All), detail view (`/log/:id`)
- Trends screen: four `fl_chart` charts (symptom frequency, top trigger foods, energy/mood, meal type distribution), date range chips, loading skeletons
- Health Profile screen: allergen chips (Big 9 + custom), conditions free-text, dietary protocols, medications
- All screens wired to FastAPI endpoints via `core/api/hearty_api_client.dart`

### Activation Prompt

```
You are implementing Phase 5 (Meal, Symptom & Wellbeing Logging) of the Hearty Android App (Spec 04).

Working directory: /home/evan/projects/food-journal-assistant
Flutter binary: /home/evan/tools/flutter/bin/flutter

Before starting:
1. Run Phase 0 (Review & Align) using its activation prompt to confirm environment and phase status.
2. Mark Phase 5 as 🟡 In Progress in docs/superpowers/plans/2026-05-04-hearty-04-android-app-plan.md.

Spec references for this phase:
- Section 9.2 — Home screen layout (timeline, wellbeing snapshot card, Quick Log FAB)
- Section 9.3 — Log Entry screen (voice button, text field, camera button, chips, review card)
- Section 9.4 — History screen (date-grouped timeline, search bar, filter chips, detail view)
- Section 9.5 — Trends screen (four fl_chart charts, date range chips, loading skeletons)
- Section 9.6 — Health Profile screen (allergen chips, conditions, protocols, medications)
- Section 11.1 — FastAPI endpoint list (meals, symptoms, wellbeing, trends, preferences)

Key deliverables (all defined above in this plan — implement them now, do not rewrite the plan):
- Log Entry screen: voice button, text field, camera button, recent-meal chips, review card with "Log it" confirmation
- Home screen: today's timeline, wellbeing snapshot card, Quick Log FAB with voice/text/camera sub-actions
- History screen: date-grouped timeline, keyword search, filter chips, detail view (/log/:id)
- Trends screen: four fl_chart charts, date range chips, loading skeletons
- Health Profile screen: allergen chips (Big 9 + custom), conditions, protocols, medications
- All screens wired to FastAPI via core/api/hearty_api_client.dart

Completion criteria:
- flutter analyze passes with zero errors
- Every new screen renders without runtime exceptions in debug mode
- Mark Phase 5 🟢 Completed in the plan
- Run /compact, then start Phase 6 using its activation prompt
```

**Deviation Log:** _None_

---

## Phase 6: Offline Queue & Background Sync

**Status:** 🟢 Completed  
**Goal:** Implement transparent offline support — Drift SQLite queue, online-first with offline fallback in the API client, connectivity-triggered sync, WorkManager background sync, and UI indicators.  
**Depends on:** Phase 5  
**Type:** Claude

**Key deliverables:**
- `core/offline/` — Drift database with `OfflineQueue` table (schema from spec: `action_type`, `payload`, `retry_count`, `status`)
- `core/api/` — `RetryInterceptor` catches `OfflineException` and writes to queue; calling code is unaware of local vs. remote save
- `core/sync/sync_service.dart` — `connectivity_plus` subscription; replays pending queue on connectivity restore, increments retry_count on 5xx (max 5), marks `failed` on non-5xx
- WorkManager periodic sync task (every 15 min when online) via `workmanager` package
- UI indicators: offline amber chip in app bar, linear progress bar during sync, persistent "Some logs couldn't sync" banner on failed rows

### Activation Prompt

```
You are implementing Phase 6 (Offline Queue & Background Sync) of the Hearty Android App (Spec 04).

Working directory: /home/evan/projects/food-journal-assistant
Flutter binary: /home/evan/tools/flutter/bin/flutter

Before starting:
1. Run Phase 0 (Review & Align) using its activation prompt to confirm environment and phase status.
2. Mark Phase 6 as 🟡 In Progress in docs/superpowers/plans/2026-05-04-hearty-04-android-app-plan.md.

Spec references for this phase:
- Section 6.1 — Drift OfflineQueue table schema (action_type, payload, retry_count, status)
- Section 6.2 — Online-first with offline fallback (RetryInterceptor in core/api/)
- Section 6.3 — Background sync logic (connectivity_plus, WorkManager, retry rules)
- Section 6.4 — UI indicators (offline chip, sync progress bar, failed banner)

Key deliverables (all defined above in this plan — implement them now, do not rewrite the plan):
- core/offline/: Drift database with OfflineQueue table matching spec schema exactly
- core/api/: RetryInterceptor catches OfflineException, writes to queue transparently
- core/sync/sync_service.dart: connectivity_plus subscription, replays queue on restore,
  increments retry_count on 5xx (max 5), marks failed on non-5xx
- WorkManager periodic sync task every 15 min via workmanager package
- UI: offline amber chip in app bar, linear progress bar during sync, persistent failed banner

Completion criteria:
- flutter analyze passes with zero errors
- Offline round-trip verified: log with network off → reconnect → confirm queue drains
- Mark Phase 6 🟢 Completed in the plan
- Run /compact, then start Phase 7 using its activation prompt
```

**Deviation Log:** _None_

---

## Phase 7: Camera & Photo Types

**Status:** 🟢 Completed  
**Goal:** Implement the full camera capture flow with all four photo types (food plate, barcode, nutrition label, food label), type selector, upload to FastAPI, processing status display, and allergen warning rendering.  
**Depends on:** Phases 2–3  
**Type:** Claude

**Key deliverables:**
- `features/photos/` — mode picker bottom sheet (Photo / Scan Barcode); still photos via `image_picker` (native camera); barcode scanning via dedicated `mobile_scanner` full-screen screen (`camera` package used only to capture a frame on barcode detection)
- Photo type selector bottom sheet; auto-pre-select Barcode when barcode path taken
- Multipart POST to `POST /api/photos` with `type` field (`food_plate`, `barcode`, `nutrition_label`, `food_label`); poll `GET /api/photos/{id}/status` for results
- Processing status UI: spinner with contextual label per photo type
- Results review screen: editable fields pre-populated from API response, "Looks good → Save" confirmation
- Allergen warning banner displayed prominently when health profile allergen match is returned

**Phase 0 findings (2026-05-08):**
- Photo endpoint stubs were NOT added in Phase 3 — `hearty_api_client.dart` has no photo methods; Phase 7 creates them from scratch.
- Spec drift corrected: REST API spec (Section 5.13/5.14) uses a SINGLE endpoint `POST /api/photos` with a `type` field, not separate per-type URLs. Plan updated to reflect this.

### Activation Prompt

```
You are implementing Phase 7 (Camera & Photo Types) of the Hearty Android App (Spec 04).

Working directory: /home/evan/projects/food-journal-assistant
Flutter binary: /home/evan/tools/flutter/bin/flutter

Before starting:
1. Run Phase 0 (Review & Align) using its activation prompt to confirm environment and phase status.
2. Mark Phase 7 as 🟡 In Progress in docs/superpowers/plans/2026-05-04-hearty-04-android-app-plan.md.

Spec references for this phase:
- Section 5.1 — Packages: camera (capture), mobile_scanner (barcode)
- Section 5.2 — Four photo types and their backend endpoints
- Section 5.3 — Full capture flow (viewfinder → type selector → upload → status → review)
- Section 5.4 — Allergen flagging display rules

Key deliverables (all defined above in this plan — implement them now, do not rewrite the plan):
- features/photos/: mode picker (Photo / Scan Barcode); image_picker for still photos; mobile_scanner + camera for barcode capture
- Photo type selector bottom sheet; auto-pre-select Barcode when barcode path taken
- Multipart POST to /api/photos/analyze, /api/photos/barcode, /api/photos/nutrition-label, /api/photos/food-label
- Processing status UI: spinner with contextual label per photo type
- Results review screen: editable fields pre-populated from API response, "Looks good → Save" confirmation
- Allergen warning banner when health profile match returned

Completion criteria:
- flutter analyze passes with zero errors
- All four photo type routes reach the results review screen in debug mode
- Mark Phase 7 🟢 Completed in the plan
- Run /compact, then start Phase 8 using its activation prompt
```

**Deviation Log:** _None_

---

## Phase 8: Notification System

**Status:** 🔴 Not Started  
**Goal:** Implement both notification paths (FCM for server-triggered and local for on-device), register Android notification channels, wire up FCM token delivery to the API, and build the Notification Preferences screen.  
**Depends on:** Phases 3, 5  
**Type:** Mixed (manual Firebase project setup + Claude implementation)

**Key deliverables:**
- **Pre-phase manual step:** Firebase project linked to Android app (`google-services.json` placed in `android/app/`)
- Four Android notification channels registered at app startup (`hearty_meal_followup`, `hearty_daily_checkin`, `hearty_digest`, `hearty_system`)
- FCM token retrieved on launch and sent to FastAPI via `PUT /api/preferences`; foreground `onMessage` displayed as local notification
- Background/terminated notification tap routing to correct GoRouter deep links (`/log`, `/home`)
- `flutter_local_notifications` daily check-in scheduled at user-configured time (default 8:00 AM)
- Notification Preferences screen: per-type toggles, nudge delay slider (30–90 min), daily time picker, wake word detection toggle (starts/stops `HeartyWakeWordService`)

### Activation Prompt

```
You are implementing Phase 8 (Notification System) of the Hearty Android App (Spec 04).

Working directory: /home/evan/projects/food-journal-assistant
Flutter binary: /home/evan/tools/flutter/bin/flutter

Before starting:
1. Run Phase 0 (Review & Align) using its activation prompt to confirm environment and phase status.
2. Confirm the pre-phase manual step is done: hearty_app/android/app/google-services.json must exist.
   If it does not exist, stop and tell the user — Firebase project setup must be completed first.
3. Mark Phase 8 as 🟡 In Progress in docs/superpowers/plans/2026-05-04-hearty-04-android-app-plan.md.

Spec references for this phase:
- Section 7.1 — Two notification paths: FCM (firebase_messaging) + local (flutter_local_notifications)
- Section 7.2 — Post-meal follow-up nudge (FCM, server-triggered, nudge_delay_minutes)
- Section 7.3 — Daily check-in (local, default 8:00 AM)
- Section 7.4 — Weekly digest (FCM, Sunday morning)
- Section 7.5 — Notification Preferences screen (toggles, delay slider, time picker, wake word toggle)
- Section 7.6 — Four Android notification channels to register at startup

Key deliverables (all defined above in this plan — implement them now, do not rewrite the plan):
- Four Android notification channels registered at app startup
  (hearty_meal_followup, hearty_daily_checkin, hearty_digest, hearty_system)
- FCM token retrieved on launch, sent to FastAPI via PUT /api/preferences
- Foreground onMessage displayed as local notification
- Background/terminated tap routing to correct GoRouter deep links (/log, /home)
- flutter_local_notifications daily check-in at user-configured time (default 8:00 AM)
- Notification Preferences screen: per-type toggles, nudge delay slider (30–90 min),
  daily time picker, wake word detection toggle (starts/stops HeartyWakeWordService)

Completion criteria:
- flutter analyze passes with zero errors
- Notification channels visible in device Settings → Apps → Hearty → Notifications
- Mark Phase 8 🟢 Completed in the plan
- Run /compact, then start Phase 9 using its activation prompt
```

**Deviation Log:** _None_

---

## Phase 9: Integration Test

**Status:** 🔴 Not Started  
**Goal:** Run end-to-end integration tests covering the core user flows against a live Supabase + FastAPI environment to confirm the app is shippable.  
**Depends on:** Phases 1–8  
**Type:** Claude

**Key deliverables:**
- Voice log flow: speak a meal → verify log entry created in Supabase
- Photo flow: capture food plate → confirm processing status resolves to `complete`
- Offline flow: disable network, log a meal, re-enable, verify queue drains and entry syncs
- Auth flow: sign out → sign back in → verify timeline data persists
- Notification flow: log a meal → confirm FCM post-meal nudge fires within nudge delay window
- All four Flutter widget trees render without `flutter analyze` errors or runtime exceptions in debug mode

### Activation Prompt

```
You are implementing Phase 9 (Integration Test) of the Hearty Android App (Spec 04).

Working directory: /home/evan/projects/food-journal-assistant
Flutter binary: /home/evan/tools/flutter/bin/flutter

Before starting:
1. Run Phase 0 (Review & Align) using its activation prompt to confirm environment and phase status.
2. Confirm Phases 1–8 are all 🟢 Completed in the plan — Phase 9 depends on all of them.
3. Mark Phase 9 as 🟡 In Progress in docs/superpowers/plans/2026-05-04-hearty-04-android-app-plan.md.

Prerequisites:
- Live Supabase project running (from Spec 01)
- FastAPI server running and reachable (from Spec 03)
- Firebase project linked and google-services.json in place (from Phase 8)
- A physical Android device or emulator connected

Integration test flows to run (in order):
1. Voice log flow: speak a meal → verify log entry created in Supabase meals table
2. Photo flow: capture a food plate photo → confirm processing status resolves to "complete"
3. Offline flow: disable network → log a meal → re-enable → verify queue drains and entry syncs
4. Auth flow: sign out → sign back in → verify timeline data persists
5. Notification flow: log a meal → confirm FCM post-meal nudge fires within nudge_delay_minutes window

Code quality gate:
- flutter analyze must pass with zero errors across the entire hearty_app codebase
- No runtime exceptions in debug mode across all four bottom-tab screens

Completion criteria:
- All five integration test flows pass
- flutter analyze passes with zero errors
- Mark Phase 9 🟢 Completed in the plan
- The app is shippable — proceed to use superpowers:finishing-a-development-branch
```

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X, Task Y — changed X because Y`_

2026-05-08 — Phase 7 — Plan listed separate photo endpoints (`/api/photos/analyze` etc.) but REST API spec (Section 5.13) defines a single `POST /api/photos` endpoint with a `type` field. Implementing against the spec. Also: photo stubs were not added in Phase 3 as previously assumed; Phase 7 creates them from scratch.
2026-05-08 — Phase 7 — Switched still-photo capture from custom `camera` viewfinder to `image_picker` (native camera app). User gets full device camera controls (flash, focus, zoom) for free; custom viewfinder now only used for barcode scanning. Flash toggle removed from the custom barcode scanner screen. Spec and plan updated to reflect this.

---

## Notes

- **openWakeWord `.onnx` model file:** Must be trained locally using the openWakeWord Python pipeline before Phase 4 can begin. Record ~100 samples of "Hey Hearty", run training, place output at `hearty_app/assets/wake_word/hey_hearty.onnx`. No account or API key required. Model file is committed to the repo (not a secret).
- **Android SHA-1 fingerprint (Google OAuth):** If not completed during Spec 01 Phase 3, it must be done at the start of Phase 3 of this plan. Requires `~/.android/debug.keystore` to exist (created automatically by first `flutter run` on Android).
- **Firebase `google-services.json`:** Must be added manually at the start of Phase 8. Requires a Firebase project linked to `com.hearty.app`.
- **`food_cache` table:** Lives in Spec 01 per that spec's notes. The Spec 07 plan handles the migration. This plan assumes `food_cache` exists by the time photo processing results need it (Phase 7 depends on Spec 07 being underway or complete for full nutritional data enrichment; photo upload and result display work without it).
