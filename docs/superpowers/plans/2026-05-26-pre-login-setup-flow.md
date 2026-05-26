# Pre-Login Setup Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all non-health setup (4 OS permissions + notification preferences) before the sign-in screen, using the existing dark-card wizard aesthetic, so the app is fully configured before the user ever logs in.

**Architecture:** A new `/setup` route becomes the `initialLocation`. `SetupScreen` runs the wizard and notification preferences in sequence, then calls `context.go('/home')` and lets the existing router redirect handle auth. `AppSetupSheet` gains a 4th battery-optimization step. `NotificationSetupScreen` is a new dark full-page screen that saves two toggle prefs to `SharedPreferences`; those prefs are synced to Supabase when onboarding completes. `OnboardingScreen` drops pages 2 and 3 and reads the pre-saved prefs in `_finish()`. `NotificationService.init()` stops requesting the notification permission at startup.

**Tech Stack:** Flutter, GoRouter, Riverpod, `permission_handler ^11.4.0`, `shared_preferences`, Supabase.

**Spec:** [`docs/superpowers/specs/2026-05-26-pre-login-setup-flow-design.md`](../specs/2026-05-26-pre-login-setup-flow-design.md)

**Plan Status:** ⬜ Not Started

---

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 1 | Add battery step to `AppSetupSheet` | ⬜ Not Started |
| 2 | Create `SetupScreen` coordinator | ⬜ Not Started |
| 3 | Create `NotificationSetupScreen` | ⬜ Not Started |
| 4 | Update `router.dart` | ⬜ Not Started |
| 5 | Simplify `OnboardingScreen` | ⬜ Not Started |
| 6 | Remove startup notification permission request | ⬜ Not Started |
| 7 | Smoke Test | ⬜ Not Started |

---

## Phase 1: Add Battery Step to `AppSetupSheet`

**Status:** ⬜ Not Started
**Goal:** Extend the 3-step wizard to 4 steps by adding battery optimization as the final step. Update all chaining methods so mic → overlay → notification → battery runs in sequence.

**Files:**
- Modify: `hearty_app/lib/features/wake_word/widgets/app_setup_sheet.dart`

### Tasks

- [ ] **Step 1: Replace the file contents**

Overwrite `hearty_app/lib/features/wake_word/widgets/app_setup_sheet.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _SetupStep { mic, overlay, notification, battery }

/// Bottom sheet wizard for granting app setup permissions.
///
/// Shows four sequential steps — microphone, overlay, notifications, battery —
/// advancing internally without closing and reopening the sheet. Non-dismissible
/// by drag or tap-outside; the user must use one of the three action buttons.
///
/// Dismissal outcomes:
///   - "Allow" + granted  → advances to next step, or dismisses when done
///   - "Allow" + denied   → dismisses (will reappear next launch)
///   - "Skip for now"     → dismisses (will reappear next launch)
///   - "Don't show again" → writes opt-out flag, dismisses permanently
class AppSetupSheet extends StatefulWidget {
  const AppSetupSheet({super.key});

  @override
  State<AppSetupSheet> createState() => _AppSetupSheetState();
}

class _AppSetupSheetState extends State<AppSetupSheet> {
  _SetupStep _step = _SetupStep.mic;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolveInitialStep();
  }

  // Jump to the first step that is still missing.
  Future<void> _resolveInitialStep() async {
    final micGranted = await Permission.microphone.isGranted;
    if (!micGranted) return; // stay at mic (default)
    final overlayGranted = await Permission.systemAlertWindow.isGranted;
    if (!overlayGranted) {
      if (mounted) setState(() => _step = _SetupStep.overlay);
      return;
    }
    // On pre-Android-13, notification permission is implicitly granted; isGranted returns true.
    final notifGranted = await Permission.notification.isGranted;
    if (!mounted) return;
    if (!notifGranted) {
      setState(() => _step = _SetupStep.notification);
      return;
    }
    final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
    if (!mounted) return;
    if (!batteryExempt) {
      setState(() => _step = _SetupStep.battery);
    } else {
      // All granted — trigger logic should have prevented showing the wizard,
      // but pop defensively rather than showing an unnecessary step.
      Navigator.of(context).pop();
    }
  }

  Future<void> _requestMic() async {
    setState(() => _loading = true);
    final status = await Permission.microphone.request();
    if (!mounted) return;

    if (status.isGranted) {
      final overlayGranted = await Permission.systemAlertWindow.isGranted;
      if (!mounted) return;
      if (!overlayGranted) {
        setState(() { _loading = false; _step = _SetupStep.overlay; });
        return;
      }
      final notifGranted = await Permission.notification.isGranted;
      if (!mounted) return;
      if (!notifGranted) {
        setState(() { _loading = false; _step = _SetupStep.notification; });
        return;
      }
      final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
      if (!mounted) return;
      if (!batteryExempt) {
        setState(() { _loading = false; _step = _SetupStep.battery; });
        return;
      }
      setState(() => _loading = false);
      Navigator.of(context).pop();
    } else {
      // Denied — dismiss, reappear next launch.
      setState(() => _loading = false);
      Navigator.of(context).pop();
    }
  }

  Future<void> _requestOverlay() async {
    setState(() => _loading = true);
    // permission_handler opens ACTION_MANAGE_OVERLAY_PERMISSION and awaits return.
    await Permission.systemAlertWindow.request();
    if (!mounted) return;

    // Re-check: user may have navigated back without granting.
    final overlayGranted = await Permission.systemAlertWindow.isGranted;
    if (!mounted) return;
    if (!overlayGranted) {
      // Not granted — dismiss, reappear next launch.
      setState(() => _loading = false);
      Navigator.of(context).pop();
      return;
    }

    final notifGranted = await Permission.notification.isGranted;
    if (!mounted) return;
    if (!notifGranted) {
      setState(() { _loading = false; _step = _SetupStep.notification; });
      return;
    }
    final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
    if (!mounted) return;
    if (!batteryExempt) {
      setState(() { _loading = false; _step = _SetupStep.battery; });
      return;
    }
    setState(() => _loading = false);
    Navigator.of(context).pop();
  }

  Future<void> _requestNotification() async {
    setState(() => _loading = true);
    await Permission.notification.request();
    if (!mounted) return;

    final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
    if (!mounted) return;
    if (!batteryExempt) {
      setState(() { _loading = false; _step = _SetupStep.battery; });
      return;
    }
    setState(() => _loading = false);
    Navigator.of(context).pop();
  }

  Future<void> _requestBattery() async {
    setState(() => _loading = true);
    await Permission.ignoreBatteryOptimizations.request();
    if (!mounted) return;
    setState(() => _loading = false);
    // Granted or denied — wizard is done.
    Navigator.of(context).pop();
  }

  Future<void> _optOut() async {
    if (_loading) return;
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    // Key kept as 'wake_word_setup_opted_out' for backward compat with existing opt-outs.
    await prefs.setBool('wake_word_setup_opted_out', true);
    if (mounted) Navigator.of(context).pop();
  }

  void _skip() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: switch (_step) {
        _SetupStep.mic => _PermissionStep(
            icon: '🎙️',
            title: 'Microphone access',
            body:
                'Hearty needs to hear you say "Hey Hearty" to start listening — even when your screen is off.',
            primaryLabel: 'Allow microphone',
            loading: _loading,
            onPrimary: _requestMic,
            onSkip: _skip,
            onOptOut: _optOut,
          ),
        _SetupStep.overlay => _PermissionStep(
            icon: '📲',
            title: 'Appear instantly',
            body:
                'When you say "Hey Hearty", the app opens automatically — no matter what screen you\'re on or if the display is off.',
            primaryLabel: 'Go to Settings',
            loading: _loading,
            onPrimary: _requestOverlay,
            onSkip: _skip,
            onOptOut: _optOut,
          ),
        _SetupStep.notification => _PermissionStep(
            icon: '🔔',
            title: 'Stay in the loop',
            body:
                'Hearty sends gentle reminders to log your meals and check in on how you\'re feeling throughout the day.',
            primaryLabel: 'Allow notifications',
            loading: _loading,
            onPrimary: _requestNotification,
            onSkip: _skip,
            onOptOut: _optOut,
          ),
        _SetupStep.battery => _PermissionStep(
            icon: '🔋',
            title: 'Run in the background',
            body:
                "Hearty needs to keep listening even when you're not using it. This prevents Android from putting it to sleep.",
            primaryLabel: 'Allow',
            loading: _loading,
            onPrimary: _requestBattery,
            onSkip: _skip,
            onOptOut: _optOut,
          ),
      },
    );
  }
}

class _PermissionStep extends StatelessWidget {
  final String icon;
  final String title;
  final String body;
  final String primaryLabel;
  final bool loading;
  final VoidCallback onPrimary;
  final VoidCallback onSkip;
  final VoidCallback onOptOut;

  const _PermissionStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.loading,
    required this.onPrimary,
    required this.onSkip,
    required this.onOptOut,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(icon, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : onPrimary,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('$primaryLabel →'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: loading ? null : onOptOut,
                child: const Text(
                  "Don't show again",
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white38,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              TextButton(
                onPressed: loading ? null : onSkip,
                child: const Text('Skip for now',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/features/wake_word/widgets/app_setup_sheet.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/features/wake_word/widgets/app_setup_sheet.dart
git commit -m "feat: add battery optimization step to AppSetupSheet wizard"
```

---

## Phase 2: Create `SetupScreen` Coordinator

**Status:** ⬜ Not Started
**Goal:** Create the `/setup` route screen that runs the wizard and notification prefs in sequence, then forwards to the normal auth flow.

**Files:**
- Create: `hearty_app/lib/features/setup/screens/setup_screen.dart`

### Tasks

- [ ] **Step 1: Create the directory and file**

```bash
mkdir -p hearty_app/lib/features/setup/screens
```

Create `hearty_app/lib/features/setup/screens/setup_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../wake_word/widgets/app_setup_sheet.dart';

/// Coordinator screen shown on every app launch.
///
/// Runs the permission wizard (AppSetupSheet) and the notification preferences
/// screen (NotificationSetupScreen) in sequence if either is incomplete, then
/// forwards to /home — the router's redirect takes over from there (sign-in if
/// not authenticated, onboarding if profile incomplete, home otherwise).
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSetup());
  }

  Future<void> _runSetup() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();

    // --- Permission wizard ---
    final optedOut = prefs.getBool('wake_word_setup_opted_out') ?? false;
    final micGranted = await Permission.microphone.isGranted;
    final overlayGranted = await Permission.systemAlertWindow.isGranted;
    final notifGranted = await Permission.notification.isGranted;
    final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
    final wizardDone =
        optedOut || (micGranted && overlayGranted && notifGranted && batteryExempt);

    if (!wizardDone) {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.black87,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        isDismissible: false,
        enableDrag: false,
        builder: (_) => const AppSetupSheet(),
      );
    }

    if (!mounted) return;

    // --- Notification preferences ---
    final notifPrefsConfigured =
        prefs.getBool('notification_prefs_configured') ?? false;
    if (!notifPrefsConfigured) {
      await context.push('/notification-setup');
    }

    if (!mounted) return;
    // Forward to normal auth flow — router redirect handles the rest.
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    // Solid black while setup runs — matches wizard background so no flash.
    return const Scaffold(backgroundColor: Colors.black);
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/features/setup/screens/setup_screen.dart
```

Expected: No issues found. (The `AppSetupSheet` import resolves because Phase 1 already exists. The `/notification-setup` route name will be wired in Phase 4.)

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/features/setup/screens/setup_screen.dart
git commit -m "feat: add SetupScreen coordinator for pre-login permission + prefs flow"
```

---

## Phase 3: Create `NotificationSetupScreen`

**Status:** ⬜ Not Started
**Goal:** Create the dark full-page notification preferences screen shown once pre-login. Two toggles; saves state to `SharedPreferences` and returns.

**Files:**
- Create: `hearty_app/lib/features/setup/screens/notification_setup_screen.dart`

### Tasks

- [ ] **Step 1: Create the file**

Create `hearty_app/lib/features/setup/screens/notification_setup_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pre-login notification preferences screen.
///
/// Shown once after the permission wizard. Saves toggle state to
/// SharedPreferences under 'notification_post_meal_enabled' and
/// 'notification_checkin_enabled'. OnboardingScreen reads these keys when
/// _finish() syncs the profile to Supabase.
class NotificationSetupScreen extends StatefulWidget {
  const NotificationSetupScreen({super.key});

  @override
  State<NotificationSetupScreen> createState() =>
      _NotificationSetupScreenState();
}

class _NotificationSetupScreenState extends State<NotificationSetupScreen> {
  bool _postMealEnabled = true;
  bool _checkinEnabled = true;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_prefs_configured', true);
    await prefs.setBool('notification_post_meal_enabled', _postMealEnabled);
    await prefs.setBool('notification_checkin_enabled', _checkinEnabled);
    if (mounted) context.pop();
  }

  Future<void> _skip() async {
    if (_saving) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_prefs_configured', true);
    // Keep defaults when skipping.
    await prefs.setBool('notification_post_meal_enabled', true);
    await prefs.setBool('notification_checkin_enabled', true);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🔔', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                'Your reminders',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hearty will check in after meals and at set times each day. '
                'You can adjust these anytime in Settings.',
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _ToggleRow(
                label: 'Post-meal reminders',
                subtitle: '30 min after logging a meal',
                value: _postMealEnabled,
                onChanged: (v) => setState(() => _postMealEnabled = v),
              ),
              const SizedBox(height: 4),
              _ToggleRow(
                label: 'Daily check-ins',
                subtitle: 'Morning, midday, and evening',
                value: _checkinEnabled,
                onChanged: (v) => setState(() => _checkinEnabled = v),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Looks good →'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _saving ? null : _skip,
                child: const Text(
                  'Skip for now',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      activeColor: Theme.of(context).colorScheme.primary,
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/features/setup/screens/notification_setup_screen.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/features/setup/screens/notification_setup_screen.dart
git commit -m "feat: add NotificationSetupScreen dark-card pre-login preferences screen"
```

---

## Phase 4: Update `router.dart`

**Status:** ⬜ Not Started
**Goal:** Change `initialLocation` to `/setup`, add the two new routes, update the redirect to leave them alone when unauthenticated, and simplify `_initWakeWord()` to only start the wake word service.

**Files:**
- Modify: `hearty_app/lib/app/router.dart`

### Tasks

- [ ] **Step 1: Add new imports**

In `hearty_app/lib/app/router.dart`, add these two imports alongside the existing feature imports (after the existing import block, before the `navigatorKey` declaration):

```dart
import '../features/setup/screens/setup_screen.dart';
import '../features/setup/screens/notification_setup_screen.dart';
```

Remove these two imports that are no longer needed in this file:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import '../features/wake_word/widgets/app_setup_sheet.dart';
```

- [ ] **Step 2: Add route name constants**

In the `Routes` class, add:

```dart
  static const String setup = 'setup';
  static const String notificationSetup = 'notification-setup';
```

- [ ] **Step 3: Change `initialLocation` and update redirect**

Find the `GoRouter(` constructor call. Change:

```dart
    initialLocation: '/home',
```

to:

```dart
    initialLocation: '/setup',
```

In the `redirect` function, find:

```dart
      if (!isAuthenticated && !isOnSignIn) return '/sign-in';
```

Replace with:

```dart
      final isOnSetup = location == '/setup';
      final isOnNotificationSetup = location == '/notification-setup';
      if (!isAuthenticated && !isOnSignIn && !isOnSetup && !isOnNotificationSetup) {
        return '/sign-in';
      }
```

- [ ] **Step 4: Add the two new routes**

In the `routes` list (after the existing `/wellbeing/log` `GoRoute` and before the closing `]`), add:

```dart
      GoRoute(
        path: '/setup',
        name: Routes.setup,
        builder: (context, state) => const SetupScreen(),
      ),
      GoRoute(
        path: '/notification-setup',
        name: Routes.notificationSetup,
        builder: (context, state) => const NotificationSetupScreen(),
      ),
```

- [ ] **Step 5: Simplify `_initWakeWord()`**

Find the existing `_initWakeWord()` method in `_ScaffoldWithNavBarState` and replace it entirely with:

```dart
  Future<void> _initWakeWord() async {
    final micGranted = await Permission.microphone.isGranted;
    if (micGranted) WakeWordChannel.startService().catchError((_) {});
  }
```

- [ ] **Step 6: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/app/router.dart
```

Expected: No issues found.

- [ ] **Step 7: Run Flutter tests**

```bash
cd hearty_app && flutter test
```

Expected: All tests pass (pre-existing failures in `voice_provider_test.dart` are unrelated and acceptable).

- [ ] **Step 8: Commit**

```bash
git add hearty_app/lib/app/router.dart
git commit -m "feat: move setup flow to pre-login /setup route, simplify _initWakeWord"
```

---

## Phase 5: Simplify `OnboardingScreen`

**Status:** ⬜ Not Started
**Goal:** Remove pages 2 (notifications) and 3 (battery) from onboarding. Update `_finish()` to read the notification prefs already stored in `SharedPreferences` by `NotificationSetupScreen` and sync them to Supabase.

**Files:**
- Modify: `hearty_app/lib/features/logging/screens/onboarding_screen.dart`

### Tasks

- [ ] **Step 1: Replace the file contents**

Overwrite `hearty_app/lib/features/logging/screens/onboarding_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/router.dart';
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/api/models/user_preferences.dart';
import '../../../core/widgets/health_profile/allergens_section.dart';
import '../../../core/widgets/health_profile/conditions_section.dart';
import '../../../core/widgets/health_profile/dietary_protocols_section.dart';
import '../../../core/widgets/health_profile/medications_section.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  List<String> _allergens = [];
  List<String> _conditions = [];
  List<String> _protocols = [];
  List<String> _medications = [];

  Future<void> _markOnboardingComplete() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('user_profiles')
            .upsert({'id': user.id}, onConflict: 'id');
      } catch (_) {
        // Non-fatal: router will re-check on next auth event.
      }
    }
  }

  Future<void> _finish() async {
    await _markOnboardingComplete();
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing =
          ref.read(preferencesProvider).valueOrNull ?? const UserPreferences();
      await ref.read(preferencesProvider.notifier).save(
            existing.copyWith(
              allergens: _allergens,
              conditions: _conditions,
              dietaryProtocols: _protocols,
              medications: _medications,
              // Sync notification prefs captured pre-login in NotificationSetupScreen.
              postMealNudgeEnabled:
                  prefs.getBool('notification_post_meal_enabled') ?? true,
              dailyCheckinEnabled:
                  prefs.getBool('notification_checkin_enabled') ?? true,
            ),
          );
    } catch (_) {
      // Non-fatal: user can update in Settings.
    }
    if (mounted) context.goNamed(Routes.home);
  }

  Future<void> _skipToHome() async {
    await _markOnboardingComplete();
    if (mounted) context.goNamed(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text('Tell us about your health',
                  style: textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                "We'll use this to personalize your experience.",
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              Text('Known allergens', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              AllergensSection(
                selected: _allergens,
                onChanged: (v) => setState(() => _allergens = v),
              ),
              const SizedBox(height: 24),
              Text('Known conditions', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              ConditionsSection(
                selected: _conditions,
                onChanged: (v) => setState(() => _conditions = v),
              ),
              const SizedBox(height: 24),
              Text('Dietary protocols', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              DietaryProtocolsSection(
                selected: _protocols,
                onChanged: (v) => setState(() => _protocols = v),
              ),
              const SizedBox(height: 24),
              Text('Medications & supplements', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              MedicationsSection(
                medications: _medications,
                onChanged: (v) => setState(() => _medications = v),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _skipToHome,
                    child: const Text('Skip'),
                  ),
                  ElevatedButton(
                    onPressed: _finish,
                    child: const Text('Finish'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/features/logging/screens/onboarding_screen.dart
```

Expected: No issues found.

- [ ] **Step 3: Run Flutter tests**

```bash
cd hearty_app && flutter test
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add hearty_app/lib/features/logging/screens/onboarding_screen.dart
git commit -m "feat: simplify onboarding to health profile only, sync pre-login notification prefs"
```

---

## Phase 6: Remove Startup Notification Permission Request

**Status:** ⬜ Not Started
**Goal:** Stop `NotificationService.init()` from requesting notification permission at app startup. The wizard's notification step owns that request now.

**Files:**
- Modify: `hearty_app/lib/core/services/notification_service.dart`

### Tasks

- [ ] **Step 1: Remove the permission request block**

In `hearty_app/lib/core/services/notification_service.dart`, find and remove these lines (currently lines 48–53):

```dart
    // Request permission (Android 13+; no-op on older versions).
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
```

The surrounding code before (`await _createChannels();`) and after (`// Display FCM messages...`) stays unchanged.

- [ ] **Step 2: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/core/services/notification_service.dart
```

Expected: No issues found.

- [ ] **Step 3: Run Flutter tests**

```bash
cd hearty_app && flutter test
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add hearty_app/lib/core/services/notification_service.dart
git commit -m "feat: remove startup notification permission request — wizard owns it now"
```

---

## Phase 7: Smoke Test

**Status:** ⬜ Not Started
**Goal:** Verify the full pre-login setup flow works end-to-end: wizard fires first, notification prefs screen follows, then sign-in, then health profile only.

### Tasks

- [ ] **Step 1: Uninstall and build fresh**

On the test device, uninstall Hearty completely (removes all permission grants and SharedPreferences). Then:

```bash
make run
```

- [ ] **Step 2: Test the full grant path**

1. App opens → black screen → wizard bottom sheet appears (🎙️ Microphone step).
2. Grant all 4 permissions through the wizard (mic → overlay → notification → battery).
3. Wizard dismisses → "Your reminders" dark screen appears.
4. Both toggles are on by default. Tap **Looks good →**.
5. Sign-in screen appears.
6. Sign in with Google account.
7. Onboarding screen appears — health profile only (no notification page, no battery page).
8. Fill in health profile → tap **Finish**.
9. Home screen appears. Wake word service notification visible in status bar.

- [ ] **Step 3: Test "Skip for now" on wizard**

1. Uninstall, `make run`.
2. Wizard appears. Tap **Skip for now**.
3. "Your reminders" screen appears. Tap **Skip for now**.
4. Sign-in screen appears.
5. Relaunch app (without uninstalling) → wizard appears again (skip does not persist).

- [ ] **Step 4: Test "Don't show again" opt-out**

1. Wizard appears. Tap **Don't show again**.
2. "Your reminders" screen appears (opt-out is for wizard only — notification prefs screen still shows).
3. Complete notification prefs.
4. Sign-in.
5. Relaunch → wizard does NOT appear. Notification prefs screen does NOT appear (already configured). Goes straight to sign-in.

- [ ] **Step 5: Test returning authenticated user**

1. Sign in and complete full setup.
2. Force-close the app and reopen.
3. Black screen flash → straight to home (setup complete, wizard and prefs skipped).
4. Wake word service starts normally.

- [ ] **Step 6: Verify notification permission not prompted at startup**

1. Uninstall, revoke all permissions.
2. `make run`.
3. Confirm the **first** thing that appears is the dark wizard bottom sheet — NOT Android's default "Allow hearty_app to send you notifications?" system dialog.

- [ ] **Step 7: Commit any smoke-test fixes**

```bash
git add -p
git commit -m "fix: smoke test corrections for pre-login setup flow"
```

---

## Deviation Log

*(append deviations here as they are discovered)*
