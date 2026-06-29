import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../app/theme/aurora_colors.dart';
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
              conversationStyle:
                  prefs.getString('conversation_style') ?? 'warm',
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
              conversationStyle:
                  prefs.getString('conversation_style') ?? 'warm',
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
    return Theme(
      data: AppTheme.aurora,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: Aurora.background),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'Tell us about your health',
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Aurora.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "We'll use this to personalize your experience.",
                    style: textTheme.bodyMedium?.copyWith(
                      color: Aurora.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _GlassSection(
                    title: 'Known allergens',
                    child: AllergensSection(
                      selected: _allergens,
                      onChanged: (v) => setState(() => _allergens = v),
                      aurora: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _GlassSection(
                    title: 'Known conditions',
                    child: ConditionsSection(
                      selected: _conditions,
                      onChanged: (v) => setState(() => _conditions = v),
                      aurora: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _GlassSection(
                    title: 'Dietary protocols',
                    child: DietaryProtocolsSection(
                      selected: _protocols,
                      onChanged: (v) => setState(() => _protocols = v),
                      aurora: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _GlassSection(
                    title: 'Medications & supplements',
                    child: MedicationsSection(
                      medications: _medications,
                      onChanged: (v) => setState(() => _medications = v),
                      aurora: true,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _skipToHome,
                        style: TextButton.styleFrom(
                          foregroundColor: Aurora.textMuted,
                        ),
                        child: const Text('Skip'),
                      ),
                      ElevatedButton(
                        onPressed: _finish,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Aurora.accentGreen,
                          foregroundColor: const Color(0xFF052E20),
                        ),
                        child: const Text('Finish'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aurora glass card wrapping a health-profile section with a white header.
class _GlassSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _GlassSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Aurora.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Aurora.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.labelLarge?.copyWith(
              color: Aurora.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
