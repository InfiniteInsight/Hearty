# App Setup Wizard — Add Notifications Step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing two-step wake word permission wizard (mic → overlay) to a three-step setup flow (mic → overlay → notifications), and rename the widget from `WakeWordSetupSheet` to `AppSetupSheet` to reflect its broader scope.

**Architecture:** The existing `wake_word_setup_sheet.dart` is renamed to `app_setup_sheet.dart` and the class renamed to `AppSetupSheet`. A `notification` value is added to `_SetupStep`. `_resolveInitialStep()` is updated to jump to the first missing permission across all three. `_requestOverlay()` is updated to advance to the notification step instead of always dismissing. A new `_requestNotification()` method handles the third step. `_initWakeWord()` in `router.dart` is updated to check all three permissions as the trigger condition; the wake word service start logic is unchanged (mic only).

**Tech Stack:** Flutter, `permission_handler ^11.4.0`, `shared_preferences`, GoRouter.

**Spec:** [`docs/superpowers/specs/2026-05-25-app-setup-wizard-design.md`](../specs/2026-05-25-app-setup-wizard-design.md)

**Plan Status:** ⬜ Not Started

---

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 1 | Rename + extend `AppSetupSheet` widget | ⬜ Not Started |
| 2 | Update trigger in `router.dart` | ⬜ Not Started |
| 3 | Smoke Test | ⬜ Not Started |

---

## Phase 1: Rename + Extend `AppSetupSheet` Widget

**Status:** ⬜ Not Started
**Goal:** Rename `wake_word_setup_sheet.dart` → `app_setup_sheet.dart`, rename the widget class, add `_SetupStep.notification`, update `_resolveInitialStep()` to handle three steps, update `_requestOverlay()` to advance instead of dismiss, and add `_requestNotification()`.

**Files:**
- Delete: `hearty_app/lib/features/wake_word/widgets/wake_word_setup_sheet.dart`
- Create: `hearty_app/lib/features/wake_word/widgets/app_setup_sheet.dart`

### Tasks

- [ ] **Step 1: Git-rename the file**

```bash
git mv hearty_app/lib/features/wake_word/widgets/wake_word_setup_sheet.dart \
       hearty_app/lib/features/wake_word/widgets/app_setup_sheet.dart
```

- [ ] **Step 2: Replace the file contents**

Overwrite `hearty_app/lib/features/wake_word/widgets/app_setup_sheet.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _SetupStep { mic, overlay, notification }

/// Bottom sheet wizard for granting app setup permissions.
///
/// Shows three sequential steps — microphone, overlay, then notifications —
/// advancing internally without closing and reopening the sheet. The sheet is
/// non-dismissible by drag or tap-outside; the user must use one of the three
/// action buttons.
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
    final notifGranted = await Permission.notification.isGranted;
    if (!mounted) return;
    if (!notifGranted) {
      setState(() => _step = _SetupStep.notification);
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
        setState(() {
          _loading = false;
          _step = _SetupStep.overlay;
        });
        return;
      }
      final notifGranted = await Permission.notification.isGranted;
      if (!mounted) return;
      if (!notifGranted) {
        setState(() {
          _loading = false;
          _step = _SetupStep.notification;
        });
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

    final notifGranted = await Permission.notification.isGranted;
    if (!mounted) return;
    if (!notifGranted) {
      setState(() {
        _loading = false;
        _step = _SetupStep.notification;
      });
      return;
    }
    setState(() => _loading = false);
    Navigator.of(context).pop();
  }

  Future<void> _requestNotification() async {
    setState(() => _loading = true);
    await Permission.notification.request();
    if (!mounted) return;
    setState(() => _loading = false);
    // Granted or denied — either way, wizard is done.
    Navigator.of(context).pop();
  }

  Future<void> _optOut() async {
    if (_loading) return;
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
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

- [ ] **Step 3: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/features/wake_word/widgets/app_setup_sheet.dart
```

Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add hearty_app/lib/features/wake_word/widgets/app_setup_sheet.dart \
        hearty_app/lib/features/wake_word/widgets/wake_word_setup_sheet.dart
git commit -m "feat: rename WakeWordSetupSheet → AppSetupSheet, add notifications step"
```

---

## Phase 2: Update Trigger in `router.dart`

**Status:** ⬜ Not Started
**Goal:** Update `_initWakeWord()` to check all three permissions as the trigger condition, and update the import to reference `AppSetupSheet` from the new file name. Wake word service start logic is unchanged.

**Files:**
- Modify: `hearty_app/lib/app/router.dart`

### Tasks

- [ ] **Step 1: Update the import**

In `hearty_app/lib/app/router.dart`, find:

```dart
import '../features/wake_word/widgets/wake_word_setup_sheet.dart';
```

Replace with:

```dart
import '../features/wake_word/widgets/app_setup_sheet.dart';
```

- [ ] **Step 2: Update `_initWakeWord()`**

Find the existing `_initWakeWord()` method (currently checking two permissions):

```dart
  Future<void> _initWakeWord() async {
    final prefs = await SharedPreferences.getInstance();
    final optedOut = prefs.getBool('wake_word_setup_opted_out') ?? false;

    final micGranted = await Permission.microphone.isGranted;
    final overlayGranted = await Permission.systemAlertWindow.isGranted;

    if (optedOut || (micGranted && overlayGranted)) {
      // Either fully set up or user chose not to use wake word.
      // Start the service only if mic is available.
      if (micGranted) WakeWordChannel.startService().catchError((_) {});
      return;
    }

    // One or both permissions missing and user hasn't opted out — show wizard.
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const WakeWordSetupSheet(),
    );

    // After the wizard closes (grant, skip, or opt-out), start the service
    // if mic is now granted.
    if (!mounted) return;
    final micNowGranted = await Permission.microphone.isGranted;
    if (!mounted) return;
    if (micNowGranted) WakeWordChannel.startService().catchError((_) {});
  }
```

Replace it entirely with:

```dart
  Future<void> _initWakeWord() async {
    final prefs = await SharedPreferences.getInstance();
    final optedOut = prefs.getBool('wake_word_setup_opted_out') ?? false;

    final micGranted = await Permission.microphone.isGranted;
    final overlayGranted = await Permission.systemAlertWindow.isGranted;
    final notifGranted = await Permission.notification.isGranted;

    if (optedOut || (micGranted && overlayGranted && notifGranted)) {
      // Fully set up or user opted out — start service only if mic is available.
      if (micGranted) WakeWordChannel.startService().catchError((_) {});
      return;
    }

    // At least one permission missing and user hasn't opted out — show wizard.
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

    // After wizard closes, start service if mic is now granted.
    if (!mounted) return;
    final micNowGranted = await Permission.microphone.isGranted;
    if (!mounted) return;
    if (micNowGranted) WakeWordChannel.startService().catchError((_) {});
  }
```

- [ ] **Step 3: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/app/router.dart
```

Expected: No issues.

- [ ] **Step 4: Run Flutter tests**

```bash
cd hearty_app && flutter test
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/lib/app/router.dart
git commit -m "feat: extend app setup wizard trigger to include notification permission"
```

---

## Phase 3: Smoke Test

**Status:** ⬜ Not Started
**Goal:** Verify all wizard paths work on device across all three steps and all dismissal modes.

### Tasks

- [ ] **Step 1: Reset all three permissions and build**

On the test device, revoke all three permissions for the app:
- Settings → Apps → Hearty → Permissions → revoke Microphone
- Settings → Apps → Hearty → Display over other apps → toggle off
- Settings → Apps → Hearty → Permissions → revoke Notifications

Then:

```bash
make run
```

- [ ] **Step 2: Test the full grant path**

1. App opens → bottom sheet appears on Step 1 (🎙️ Microphone access).
2. Tap **Allow microphone →** → system mic dialog → tap **Allow**.
3. Sheet advances to Step 2 (📲 Appear instantly) without closing.
4. Tap **Go to Settings →** → Android overlay settings page opens.
5. Toggle "Allow display over other apps" on → navigate back to Hearty.
6. Sheet advances to Step 3 (🔔 Stay in the loop) without closing.
7. Tap **Allow notifications →** → system notifications dialog → tap **Allow**.
8. Sheet dismisses.
9. Wake word service is running (visible in the persistent "Hearty is listening" notification).

- [ ] **Step 3: Test "Skip for now" at each step**

1. Revoke mic again. Relaunch — wizard appears on Step 1.
2. Tap **Skip for now** → sheet dismisses.
3. Relaunch again — wizard appears again (skip does not persist).
4. Grant mic but revoke overlay. Relaunch — wizard opens directly on Step 2.
5. Tap **Skip for now** → sheet dismisses.
6. Relaunch — wizard appears again on Step 2.
7. Grant mic + overlay but revoke notifications. Relaunch — wizard opens directly on Step 3.
8. Tap **Skip for now** → sheet dismisses.
9. Relaunch — wizard appears again on Step 3.

- [ ] **Step 4: Test "Don't show again" opt-out**

1. Wizard appears on any step.
2. Tap **Don't show again** → sheet dismisses.
3. Relaunch — wizard does NOT appear regardless of permission state.

- [ ] **Step 5: Commit any smoke-test fixes**

```bash
git add -p
git commit -m "fix: smoke test corrections for app setup wizard"
```

---

## Deviation Log

*(append deviations here as they are discovered)*
