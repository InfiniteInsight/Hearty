# App Setup Wizard — Three-Step Permission Flow

**Date:** 2026-05-25
**Status:** Approved

## Overview

Extend the existing two-step wake word permission wizard (mic → overlay) to a three-step flow (mic → overlay → notifications), reframed as a cohesive "set up how Hearty reaches you and how you reach it" experience. The widget is renamed from `WakeWordSetupSheet` to `AppSetupSheet` to reflect its broader scope.

All three steps live in a single non-dismissible bottom sheet that swaps content internally as the user advances — the same pattern as the existing two-step wizard.

## Trigger Logic

On every app launch, after the main scaffold mounts (`WidgetsBinding.instance.addPostFrameCallback`), check:

1. Has the user opted out? (`wake_word_setup_opted_out` in `SharedPreferences`)
2. Is microphone granted?
3. Is overlay (`Settings.canDrawOverlays`) granted?
4. Is notification permission granted? (`Permission.notification.isGranted`)

If **opted out** OR **all three granted** → skip wizard; start wake word service if mic is granted.

If **any permission is missing** AND **not opted out** → show `AppSetupSheet`, opening at the first missing step.

**Step skip logic:** The wizard opens at the first step that is still missing, in order: mic → overlay → notification. If mic is already granted but overlay and notification are not, the wizard opens at overlay. If mic and overlay are granted but notification is not, it opens directly at notification.

**Chain advance logic:** Each step, after a successful grant, checks whether the next step is needed and either advances or dismisses:
- Mic granted → check overlay; if needed advance to overlay, else check notification; if needed advance to notification, else dismiss
- Overlay granted (or user returns from Settings) → check notification; if needed advance to notification, else dismiss
- Notification granted or denied → dismiss (notification denial does not cause a reappear; the OS controls the system dialog and the user's choice is respected)

## Step 1 — Microphone

**Trigger:** Mic permission not yet granted.

**UI:**
- 🎙️ icon (large)
- Title: "Microphone access"
- Body: "Hearty needs to hear you say 'Hey Hearty' to start listening — even when your screen is off."
- Primary button: "Allow microphone →" → `Permission.microphone.request()` system dialog
- "Skip for now" → dismisses; reappears next launch
- "Don't show again" (dimmed) → `wake_word_setup_opted_out = true`; never shows again

**After dialog:**
- Granted → check overlay; advance to overlay step if needed, else advance to notification step if needed, else dismiss
- Denied → dismiss immediately; reappears next launch

## Step 2 — Display Over Other Apps

**Trigger:** Mic granted, overlay not yet granted.

**UI:**
- 📲 icon (large)
- Title: "Appear instantly"
- Body: "When you say 'Hey Hearty', the app opens automatically — no matter what screen you're on or if the display is off."
- Primary button: "Go to Settings →" → opens `ACTION_MANAGE_OVERLAY_PERMISSION` (via `Permission.systemAlertWindow.request()`)
- "Skip for now" → dismisses; reappears next launch
- "Don't show again" (dimmed) → `wake_word_setup_opted_out = true`

**After returning from Settings:**
- `permission_handler`'s `.request()` awaits the return from the Settings activity, so no `WidgetsBindingObserver` needed — the `await` resolves when the user navigates back
- Re-check `Permission.systemAlertWindow.isGranted`; if granted → check notification, advance or dismiss; if not granted → dismiss; reappears next launch

## Step 3 — Notifications

**Trigger:** Mic and overlay both granted (or user advanced past them), notification not yet granted.

**UI:**
- 🔔 icon (large)
- Title: "Stay in the loop"
- Body: "Hearty sends gentle reminders to log your meals and check in on how you're feeling throughout the day."
- Primary button: "Allow notifications →" → `Permission.notification.request()` system dialog
- "Skip for now" → dismisses; reappears next launch
- "Don't show again" (dimmed) → `wake_word_setup_opted_out = true`

**After dialog:**
- Granted or denied → dismiss (one chance; reappears next launch only if user used "Skip for now" or had not yet seen this step)

## Opt-Out Semantics

- Same `SharedPreferences` key: `wake_word_setup_opted_out = true`
- Opting out at any step covers all three steps permanently
- "Skip for now" at any step dismisses for this session; wizard reappears next launch
- No "opt back in" UI in this spec — belongs in Settings > Voice and Settings > Notifications

## Visual Design

- Same dark-themed `showModalBottomSheet` as the existing two steps: `backgroundColor: Colors.black87`, `RoundedRectangleBorder` top corners, `isDismissible: false`, `enableDrag: false`
- Same `_PermissionStep` stateless widget handles all three steps — only the content props differ
- "Don't show again" remains visually subordinate (dimmed, underlined, small font)
- "Skip for now" remains the natural secondary action

## State Storage

```
SharedPreferences key: "wake_word_setup_opted_out" (bool, default false)
```

Permission status for all three permissions is read live from the OS — no local caching.

## Implementation Touchpoints

- **Rename widget file:** `wake_word_setup_sheet.dart` → `app_setup_sheet.dart` (same directory)
- **Rename class:** `WakeWordSetupSheet` → `AppSetupSheet`, `_WakeWordSetupSheetState` → `_AppSetupSheetState`
- **Extend enum:** `_SetupStep { mic, overlay }` → `_SetupStep { mic, overlay, notification }`
- **Update `_resolveInitialStep()`:** check all three in order; set `_step` to first missing one
- **Update `_requestMic()`:** after mic granted, check overlay then notification before dismissing
- **Update `_requestOverlay()`:** after overlay check, advance to notification step if needed instead of always dismissing
- **Add `_requestNotification()`:** calls `Permission.notification.request()` then dismisses
- **Update `build()` switch:** add `_SetupStep.notification` case
- **Update `router.dart` import:** `WakeWordSetupSheet` → `AppSetupSheet` (new file name)
- **Update `router.dart` `_initWakeWord()`:** trigger condition now includes `Permission.notification.isGranted`; wake word service start logic unchanged (only needs mic)

## Out of Scope

- Re-enabling notifications or wake word after opt-out (Settings)
- iOS implementation
- Notification channel setup (already handled by existing FCM/firebase_messaging infrastructure)
- Any changes to `HeartyWakeWordService.kt`
