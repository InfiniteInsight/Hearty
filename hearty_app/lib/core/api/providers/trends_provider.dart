import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearty_api_client.dart';
import '../models/trends_data.dart';

class TrendsNotifier extends AsyncNotifier<TrendsData> {
  @override
  Future<TrendsData> build() async {
    final client = ref.watch(heartyApiClientProvider);
    return client.fetchTrends();
  }

  Future<void> refresh() async {
    final client = ref.read(heartyApiClientProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => client.fetchTrends());
  }

  Future<void> triggerAnalysis() async {
    final client = ref.read(heartyApiClientProvider);
    state = const AsyncLoading();
    try {
      await client.triggerAnalysis();
      state = await AsyncValue.guard(() => client.fetchTrends());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  // Kept for backward compat with any callers passing days.
  Future<void> setDays(int days) => refresh();
}

final trendsProvider =
    AsyncNotifierProvider<TrendsNotifier, TrendsData>(TrendsNotifier.new);
