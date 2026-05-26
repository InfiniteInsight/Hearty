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
    if (!mounted) return;
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
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing =
          ref.read(preferencesProvider).valueOrNull ?? const UserPreferences();
      await ref.read(preferencesProvider.notifier).save(
            existing.copyWith(
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
