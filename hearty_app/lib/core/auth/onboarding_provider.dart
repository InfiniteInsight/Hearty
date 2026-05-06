import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the current user has completed onboarding.
///
/// In-memory only — resets on app restart.
/// TODO Phase 5: persist onboarding completion to user_profiles
final hasCompletedOnboardingProvider = StateProvider<bool>((ref) => false);
