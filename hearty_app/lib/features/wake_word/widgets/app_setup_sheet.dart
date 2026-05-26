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
    // On pre-Android-13, notification permission is implicitly granted; isGranted returns true.
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
