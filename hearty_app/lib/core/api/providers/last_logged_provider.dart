import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the meal ID of the most recently voice-logged meal.
/// Set by VoiceNotifier after a successful first-turn log.
/// Cleared by the router after showing the edit shortcut SnackBar.
final lastLoggedMealIdProvider = StateProvider<String?>((ref) => null);
