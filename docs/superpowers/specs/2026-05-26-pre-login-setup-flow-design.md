# Pre-Login Setup Flow

**Date:** 2026-05-26
**Status:** Approved

## Overview

All non-health setup — four OS permissions and notification preferences — is presented before the sign-in screen, using the existing dark-card wizard aesthetic. Every app launch checks whether setup is complete; if not, the setup flow runs before any auth routing occurs. Post-login onboarding is simplified to health profile only.

## New Launch Sequence

```
App launch
  └─ /setup coordinator
       ├─ [wizard incomplete] → show AppSetupSheet (4 permissions)
       ├─ [notification prefs not configured] → show NotificationSetupScreen
       └─ [all done] → route normally
            ├─ unauthenticated → /sign-in
            ├─ authenticated, onboarding incomplete → /onboarding
            └─ authenticated, onboarding complete → /home
```

The `/setup` route is the router's `initialLocation`. If setup is already complete on launch, it redirects immediately with no visible delay. The router's redirect function is updated to leave `/setup` and `/notification-setup` alone (no auth redirect) so they remain accessible before sign-in.

## Setup Coordinator (`/setup` route)

A new `SetupScreen` — a `ConsumerStatefulWidget` that renders a minimal dark scaffold (same `Colors.black87` background as the wizard so it is invisible behind the sheet). On first frame:

1. Check wizard completion (see below). If incomplete → show `AppSetupSheet` as `showModalBottomSheet` (non-dismissible, same params as current).
2. After `AppSetupSheet` closes → check `notification_prefs_configured` flag.
3. If notification prefs not yet configured → push `/notification-setup`.
4. After `/notification-setup` returns → call `context.go('/home')`. The existing router redirect logic handles the rest: unauthenticated users are redirected to `/sign-in`; authenticated users without completed onboarding are redirected to `/onboarding`.

If wizard is already complete on mount and notification prefs are configured, `SetupScreen` skips both steps and routes forward on the first frame.

**Wizard completion check (all of these must be true to skip the wizard):**

```dart
final optedOut = prefs.getBool('wake_word_setup_opted_out') ?? false;
final micGranted = await Permission.microphone.isGranted;
final overlayGranted = await Permission.systemAlertWindow.isGranted;
final notifGranted = await Permission.notification.isGranted;
final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
final wizardDone = optedOut || (micGranted && overlayGranted && notifGranted && batteryExempt);
```

## The 4-Step Permission Wizard (`AppSetupSheet`)

`AppSetupSheet` gains a 4th enum value and step. Updated enum:

```dart
enum _SetupStep { mic, overlay, notification, battery }
```

**New step — 🔋 Run in the background:**

- Icon: 🔋
- Title: "Run in the background"
- Body: "Hearty needs to keep listening even when you're not using it. This prevents Android from putting it to sleep."
- Primary button: "Allow →" → `Permission.ignoreBatteryOptimizations.request()` (shows Android's in-place system dialog — no Settings redirect needed)
- "Skip for now" / "Don't show again" — same behavior as all other steps

**`_resolveInitialStep()` updated** to check all 4 in order: mic → overlay → notification → battery. Jumps to the first missing step.

**`_requestNotification()` updated** to advance to `battery` step after requesting (if battery not yet exempt), instead of always popping.

**`_requestBattery()` added** — requests `Permission.ignoreBatteryOptimizations`, then pops (granted or denied, wizard is done).

Opt-out key unchanged: `wake_word_setup_opted_out`.

## Notification Setup Screen (`/notification-setup`)

A new full-page dark screen shown once, pre-login, after the wizard. Not a bottom sheet — fills the viewport.

**UI:**
- Dark background (`Colors.black` or `Colors.black87`)
- 🔔 icon (large, centered, `fontSize: 48`)
- Title: "Your reminders" (`titleLarge`, white, bold)
- Body: "Hearty will check in after meals and at set times each day. You can adjust these anytime in Settings." (white70, centered)
- Two toggle rows (white text, standard `SwitchListTile` styled for dark theme):
  - **Post-meal reminders** — on/off toggle, default on, subtitle: "30 min after logging a meal"
  - **Daily check-ins** — on/off toggle, default on, subtitle: "Morning, midday, and evening"
- Full-width `FilledButton`: "Looks good →" — saves prefs and marks configured
- Small `TextButton` below: "Skip for now" — marks configured with defaults, advances

**Behavior:**
- Tapping either button writes the toggle state to `SharedPreferences` and sets `notification_prefs_configured = true`, then returns to the `/setup` coordinator which routes forward.
- This screen is only shown when `notification_prefs_configured` is `false`.

**Post-login sync:** When the user completes sign-in and health profile onboarding, `_markOnboardingComplete()` reads the locally-stored notification pref flags from `SharedPreferences` and writes them to the user's profile in Supabase before navigating to `/home`. This ensures preferences set before login are active when the app starts scheduling notifications.

## Post-Login Onboarding Changes

The existing 3-page onboarding (`OnboardingScreen`) becomes 1 page:

| Page | Content | Change |
|------|---------|--------|
| 1 | Health profile | Unchanged |
| ~~2~~ | ~~Notification preferences~~ | Removed — moved to pre-login `NotificationSetupScreen` |
| ~~3~~ | ~~Battery optimization~~ | Removed — moved to `AppSetupSheet` wizard |

`_markOnboardingComplete()` is updated to read local notification prefs from `SharedPreferences` and save them to Supabase as part of the profile upsert.

## Startup Notification Permission Change

`NotificationService.init()` no longer calls `FirebaseMessaging.instance.requestPermission()`. The wizard's notification step owns that request. FCM token registration and notification scheduling are unaffected — only the runtime permission request is removed from startup.

## Home Screen / Wake Word Simplification

`_initWakeWord()` in `router.dart` becomes:

```dart
Future<void> _initWakeWord() async {
  final micGranted = await Permission.microphone.isGranted;
  if (micGranted) WakeWordChannel.startService().catchError((_) {});
}
```

No wizard display. No permission checks beyond mic. The setup coordinator owns all of that.

## State Storage

| SharedPreferences Key | Type | Default | Meaning |
|----------------------|------|---------|---------|
| `wake_word_setup_opted_out` | bool | false | User opted out of permission wizard permanently |
| `notification_prefs_configured` | bool | false | User has seen notification preferences setup screen |
| `notification_post_meal_enabled` | bool | true | Post-meal reminder preference (pre-login) |
| `notification_checkin_enabled` | bool | true | Daily check-in preference (pre-login) |

## Router Changes

- `initialLocation` changes from `/home` to `/setup`
- New routes added: `/setup` → `SetupScreen`, `/notification-setup` → `NotificationSetupScreen`
- Redirect function updated: `/setup` and `/notification-setup` are excluded from the unauthenticated redirect to `/sign-in`

## Settings Screen

`NotificationPreferencesScreen` (Settings tab) is untouched. No restyling in this spec.

## Implementation Touchpoints

| File | Change |
|------|--------|
| `hearty_app/lib/app/router.dart` | New routes, new `initialLocation`, updated redirect, simplified `_initWakeWord()` |
| `hearty_app/lib/features/setup/screens/setup_screen.dart` | New — setup coordinator |
| `hearty_app/lib/features/setup/screens/notification_setup_screen.dart` | New — notification preferences dark-card screen |
| `hearty_app/lib/features/wake_word/widgets/app_setup_sheet.dart` | Add battery step, update `_requestNotification()`, add `_requestBattery()` |
| `hearty_app/lib/features/logging/screens/onboarding_screen.dart` | Remove pages 2 and 3, update `_markOnboardingComplete()` to sync local prefs |
| `hearty_app/lib/core/services/notification_service.dart` | Remove `requestPermission()` call from `init()` |

## Out of Scope

- Restyling `NotificationPreferencesScreen` in Settings
- iOS implementation
- Re-enabling wizard after opt-out (Settings > Voice, future)
- Time picker on `NotificationSetupScreen` (fine-tuning lives in Settings)
