import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearty_api_client.dart';
import '../models/user_preferences.dart';

class PreferencesNotifier extends AsyncNotifier<UserPreferences> {
  @override
  Future<UserPreferences> build() async {
    final client = ref.watch(heartyApiClientProvider);
    return client.fetchPreferences();
  }

  Future<void> save(UserPreferences prefs) async {
    final client = ref.read(heartyApiClientProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => client.savePreferences(prefs));
  }
}

final preferencesProvider =
    AsyncNotifierProvider<PreferencesNotifier, UserPreferences>(
        PreferencesNotifier.new);
