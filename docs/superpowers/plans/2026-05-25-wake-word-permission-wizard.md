# Wake Word Permission Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a step-by-step bottom sheet wizard that explains and requests microphone + "Display over other apps" permissions before starting the wake word service — appearing on every launch until both are granted or the user explicitly opts out.

**Architecture:** A single new widget (`WakeWordSetupSheet`) handles both permission steps as internal state — the sheet stays open and swaps its content when advancing from mic to overlay. The trigger logic in `_ScaffoldWithNavBarState._initWakeWord()` replaces the current bare `Permission.microphone.request()` call: it reads a `SharedPreferences` opt-out flag and live permission status, then either starts the service directly or shows the wizard. No API changes needed — this is purely Flutter-side.

**Tech Stack:** Flutter, `permission_handler ^11.4.0`, `shared_preferences`, Riverpod, GoRouter.

**Spec:** [`docs/superpowers/specs/2026-05-25-wake-word-permission-wizard-design.md`](../specs/2026-05-25-wake-word-permission-wizard-design.md)

**Plan Status:** ⬜ Not Started

---

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 1 | `WakeWordSetupSheet` widget | ⬜ Not Started |
| 2 | Trigger logic in `router.dart` | ⬜ Not Started |
| 3 | Smoke Test | ⬜ Not Started |

---

## Phase 1: `WakeWordSetupSheet` Widget

**Status:** ⬜ Not Started
**Goal:** Create the bottom sheet widget that walks through both permission steps, handles skip / opt-out / grant, and dismisses cleanly in all cases.

**Files:**
- Create: `hearty_app/lib/features/wake_word/widgets/wake_word_setup_sheet.dart`

### Tasks

- [ ] **Step 1: Create the widget file**

Create `hearty_app/lib/features/wake_word/widgets/wake_word_setup_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _SetupStep { mic, overlay }

/// Bottom sheet wizard for granting wake word permissions.
///
/// Shows two sequential steps — microphone then overlay — advancing internally
/// without closing and reopening the sheet. The sheet is non-dismissible by
/// drag or tap-outside; the user must use one of the three action buttons.
///
/// Dismissal outcomes:
///   - "Allow" + granted  → advances to next step, or dismisses when done
///   - "Allow" + denied   → dismisses (will reappear next launch)
///   - "Skip for now"     → dismisses (will reappear next launch)
///   - "Don't show again" → writes opt-out flag, dismisses permanently
class WakeWordSetupSheet extends StatefulWidget {
  const WakeWordSetupSheet({super.key});

  @override
  State<WakeWordSetupSheet> createState() => _WakeWordSetupSheetState();
}

class _WakeWordSetupSheetState extends State<WakeWordSetupSheet> {
  _SetupStep _step = _SetupStep.mic;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolveInitialStep();
  }

  // If mic is already granted (only overlay is missing), skip straight to step 2.
  Future<void> _resolveInitialStep() async {
    final micGranted = await Permission.microphone.isGranted;
    if (micGranted && mounted) setState(() => _step = _SetupStep.overlay);
  }

  Future<void> _requestMic() async {
    setState(() => _loading = true);
    final status = await Permission.microphone.request();
    if (!mounted) return;
    setState(() => _loading = false);

    if (status.isGranted) {
      final overlayGranted = await Permission.systemAlertWindow.isGranted;
      if (!mounted) return;
      if (overlayGranted) {
        Navigator.of(context).pop();
      } else {
        setState(() => _step = _SetupStep.overlay);
      }
    } else {
      // Denied or permanently denied — dismiss, show again next launch.
      Navigator.of(context).pop();
    }
  }

  Future<void> _requestOverlay() async {
    setState(() => _loading = true);
    // permission_handler opens ACTION_MANAGE_OVERLAY_PERMISSION and awaits return.
    await Permission.systemAlertWindow.request();
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pop();
  }

  Future<void> _optOut() async {
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
cd hearty_app && flutter analyze lib/features/wake_word/widgets/wake_word_setup_sheet.dart
```

Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/features/wake_word/widgets/wake_word_setup_sheet.dart
git commit -m "feat: add WakeWordSetupSheet permission wizard widget"
```

---

## Phase 2: Trigger Logic in `router.dart`

**Status:** ⬜ Not Started
**Goal:** Replace the current bare `Permission.microphone.request()` in `_initWakeWord()` with logic that reads the opt-out flag and live permission status, then either starts the service directly or shows `WakeWordSetupSheet`. Also defer `_initWakeWord()` to post-frame so the widget tree is fully built before showing a bottom sheet.

**Files:**
- Modify: `hearty_app/lib/app/router.dart`

### Tasks

- [ ] **Step 1: Add the import**

In `hearty_app/lib/app/router.dart`, add this import alongside the existing `permission_handler` import:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import '../features/wake_word/widgets/wake_word_setup_sheet.dart';
```

- [ ] **Step 2: Defer `_initWakeWord()` to post-frame**

In `_ScaffoldWithNavBarState`, find `initState` (currently around line 256):

```dart
  @override
  void initState() {
    super.initState();
    _initWakeWord();
  }
```

Replace with:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWakeWord());
  }
```

This ensures `context` is valid and the scaffold is mounted before any dialog or bottom sheet is shown.

- [ ] **Step 3: Replace `_initWakeWord()`**

Find the existing `_initWakeWord()` method (currently around line 260):

```dart
  Future<void> _initWakeWord() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return;
    WakeWordChannel.startService().catchError((_) {});
    // Request "Display over other apps" ...
    final overlayStatus = await Permission.systemAlertWindow.status;
    if (!overlayStatus.isGranted) {
      await Permission.systemAlertWindow.request();
    }
  }
```

Replace it entirely with:

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
    final micNowGranted = await Permission.microphone.isGranted;
    if (micNowGranted) WakeWordChannel.startService().catchError((_) {});
  }
```

- [ ] **Step 4: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/app/router.dart
```

Expected: No issues.

- [ ] **Step 5: Run Flutter tests**

```bash
cd hearty_app && flutter test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add hearty_app/lib/app/router.dart
git commit -m "feat: show wake word permission wizard on launch until granted or opted out"
```

---

## Phase 3: Smoke Test

**Status:** ⬜ Not Started
**Goal:** Verify all wizard paths work on device: grant, skip, opt-out, and re-launch behavior.

### Tasks

- [ ] **Step 1: Reset permissions and build**

On the test device, revoke mic and overlay permissions for the app (Settings → Apps → Hearty → Permissions → revoke Microphone; Settings → Apps → Hearty → Display over other apps → toggle off). Then:

```bash
make run
```

- [ ] **Step 2: Test the grant path**

1. App opens → bottom sheet appears with Step 1 (🎙️ Microphone access).
2. Tap **Allow microphone →** → Android system mic dialog appears → tap **Allow**.
3. Sheet should advance to Step 2 (📲 Appear instantly) without closing.
4. Tap **Go to Settings →** → Android overlay settings page opens.
5. Toggle "Allow display over other apps" on → navigate back to Hearty.
6. Sheet should dismiss automatically.
7. Wake word service should be running (visible in the persistent "Hearty is listening" notification).

- [ ] **Step 3: Test "Skip for now"**

1. Revoke mic again (Settings → Apps → Hearty → Permissions → Microphone).
2. Relaunch the app (`make run`).
3. Wizard appears again on Step 1.
4. Tap **Skip for now** → sheet dismisses.
5. Relaunch again — wizard appears again (skip does not persist).

- [ ] **Step 4: Test "Don't show again" opt-out**

1. Wizard appears on Step 1.
2. Tap **Don't show again** → sheet dismisses.
3. Relaunch — wizard does NOT appear.
4. Wake word service does NOT start (mic not granted, opted out).

- [ ] **Step 5: Test mic-only already granted**

1. Grant mic but keep overlay off.
2. Relaunch — wizard should open directly on Step 2 (📲), skipping Step 1.

- [ ] **Step 6: Commit any smoke-test fixes**

```bash
git add -p
git commit -m "fix: smoke test corrections for wake word permission wizard"
```

---

## Deviation Log

*(append deviations here as they are discovered)*
