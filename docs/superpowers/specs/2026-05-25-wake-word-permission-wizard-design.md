# Wake Word Permission Wizard

**Date:** 2026-05-25
**Status:** Approved

## Overview

A step-by-step bottom sheet wizard that walks users through granting the two Android permissions required for the "Hey Hearty" wake word feature: microphone access and "Display over other apps". The wizard appears on every app launch until the user either grants both permissions or explicitly opts out.

## Trigger Logic

On every app launch, after the main scaffold mounts, check:

1. Is microphone permission granted?
2. Is overlay permission (`canDrawOverlays`) granted?
3. Has the user opted out? (stored in `SharedPreferences` as `wake_word_setup_opted_out: bool`)

If **either permission is missing** AND **not opted out** → show the wizard starting at the first missing step.
If **both granted** OR **opted out** → do nothing (wake word service starts normally).

The wizard only advances to Step 2 (overlay) if Step 1 (microphone) is granted. If mic is denied or skipped, Step 2 is not shown that session — there is no value in overlay without mic.

## Step 1 — Microphone

**Trigger:** Mic permission not yet granted and not opted out.

**UI:** Bottom sheet with:
- Drag handle
- 🎙️ icon (large)
- Title: "Microphone access"
- Body: "Hearty needs to hear you say 'Hey Hearty' to start listening — even when your screen is off."
- Primary button: "Allow microphone →" → triggers `Permission.microphone.request()` system dialog
- Secondary link: "Skip for now" → dismisses wizard; will reappear next launch
- Tertiary link (dimmed): "Don't show again" → sets `wake_word_setup_opted_out = true`; wizard never shows again

**After system dialog:**
- Granted → widget advances internally to Step 2 (same bottom sheet, content swaps)
- Denied → sheet dismisses; wizard will reappear next launch (user did not opt out)

## Step 2 — Display Over Other Apps

**Trigger:** Mic is granted but `Settings.canDrawOverlays()` returns false and not opted out.

**UI:** Bottom sheet with:
- Drag handle
- 📲 icon (large)
- Title: "Appear instantly"
- Body: "When you say 'Hey Hearty', the app opens automatically — no matter what screen you're on or if the display is off."
- Primary button: "Go to Settings →" → opens `ACTION_MANAGE_OVERLAY_PERMISSION` system settings page
- Secondary link: "Skip for now" → dismisses; will reappear next launch
- Tertiary link (dimmed): "Don't show again" → sets `wake_word_setup_opted_out = true`

**After returning from Settings:**
- The sheet registers a `WidgetsBindingObserver` before opening Settings, listens for `AppLifecycleState.resumed`, then re-checks `canDrawOverlays()` when the app comes back to the foreground
- If granted → dismiss sheet; service starts normally
- If not granted → dismiss sheet; wizard reappears next launch

## Opt-Out Semantics

- "Don't show again" at either step writes `wake_word_setup_opted_out = true` to `SharedPreferences`
- Opting out at Step 1 implies opt-out for Step 2 as well (overlay is useless without mic)
- Opt-out is permanent unless cleared by a future "Re-enable wake word" option in Settings (out of scope for this spec)
- There is no "opt back in" UI in this spec — that belongs in Settings > Voice

## Visual Design

- Both steps are `DraggableScrollableSheet` / `showModalBottomSheet` with `isDismissible: false, enableDrag: false` — the user must use the provided buttons to dismiss (prevents accidental swipe-away that would be ambiguous between "skip" and "opt out")
- Dark theme matching the existing `VoiceOverlayScreen` (black/dark surface, white text)
- "Don't show again" is visually subordinate: smaller font, dimmed opacity, underlined — permanent action should not be the obvious tap
- "Skip for now" is the natural secondary action: full-opacity, medium weight

## State Storage

```
SharedPreferences key: "wake_word_setup_opted_out" (bool, default false)
```

Microphone and overlay grant status are read live from the OS at each launch — no local caching of permission state.

## Implementation Touchpoints

- **New widget:** `hearty_app/lib/features/wake_word/widgets/wake_word_setup_sheet.dart` — a single bottom sheet stateful widget; internally tracks `_step` (mic | overlay) and swaps content in place rather than closing and reopening the sheet. Also implements `WidgetsBindingObserver` to detect app resume after the Settings handoff.
- **New provider or helper:** `wake_word_setup_provider.dart` (or inline in router) — reads prefs + permission status, decides whether to show wizard
- **`router.dart` `_initWakeWord()`** — current permission logic replaced by: check conditions → if wizard needed, show it; otherwise start service directly
- **No changes to `HeartyWakeWordService.kt`** — the wizard is purely Flutter-side; the service starts after permissions are confirmed

## Out of Scope

- Re-enabling wake word after opt-out (belongs in Settings > Voice)
- iOS implementation
- Notification permission (handled separately at OS level)
