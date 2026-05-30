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
    final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
    final wizardDone =
        optedOut || (micGranted && overlayGranted && batteryExempt);

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

    // --- Conversation style ---
    final styleConfigured =
        prefs.getBool('conversation_style_configured') ?? false;
    if (!styleConfigured) {
      await context.push('/conversation-style-setup');
    }

    if (!mounted) return;
    // Forward to normal auth flow — router redirect handles the rest.
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    // Solid black while setup runs — matches wizard background so no flash.
    return const Scaffold(backgroundColor: Colors.black87);
  }
}
