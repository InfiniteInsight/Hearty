// lib/core/api/providers/preferences_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../offline/local_preferences_dao.dart';
import '../hearty_api_client.dart';
import '../models/user_preferences.dart';

class PreferencesNotifier extends AsyncNotifier<UserPreferences> {
  @override
  Future<UserPreferences> build() async {
    final dao = ref.watch(localPreferencesDaoProvider);
    final cached = await dao.read();
    if (cached != null) return cached;

    // No local data — bootstrap from API (first install or cleared storage).
    try {
      final client = ref.read(heartyApiClientProvider);
      final prefs = await client.fetchPreferences();
      await dao.write(prefs, syncStatus: 'synced');
      return prefs;
    } catch (_) {
      return const UserPreferences();
    }
  }

  Future<void> save(UserPreferences prefs) async {
    final dao = ref.read(localPreferencesDaoProvider);
    await dao.write(prefs, syncStatus: 'pending');
    state = AsyncData(prefs);
  }
}

final preferencesProvider =
    AsyncNotifierProvider<PreferencesNotifier, UserPreferences>(
        PreferencesNotifier.new);
