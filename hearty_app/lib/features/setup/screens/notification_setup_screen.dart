import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
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
    // Request OS notification permission first, before saving preferences.
    await Permission.notification.request();
    if (!mounted) return;
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
      activeThumbColor: Theme.of(context).colorScheme.primary,
    );
  }
}
