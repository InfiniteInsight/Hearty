// lib/core/api/providers/trends_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../offline/local_trends_dao.dart';
import '../hearty_api_client.dart';
import '../models/trends_data.dart';

class TrendsNotifier extends AsyncNotifier<TrendsData> {
  @override
  Future<TrendsData> build() async {
    final dao = ref.watch(localTrendsDaoProvider);
    final cached = await dao.read();
    if (cached != null) return cached;

    // No cache yet — try a live fetch.
    try {
      final client = ref.read(heartyApiClientProvider);
      final trends = await client.fetchTrends();
      await dao.write(trends);
      return trends;
    } catch (_) {
      return const TrendsData(
        symptomFrequency: [],
        signals: [],
        wellbeingTrend: [],
        mealTypeDistribution: {},
      );
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final client = ref.read(heartyApiClientProvider);
      final trends = await client.fetchTrends();
      await ref.read(localTrendsDaoProvider).write(trends);
      state = AsyncData(trends);
    } catch (e, st) {
      // On failure, keep showing whatever is cached.
      final cached = await ref.read(localTrendsDaoProvider).read();
      state = cached != null ? AsyncData(cached) : AsyncError(e, st);
    }
  }

  Future<void> triggerAnalysis() async {
    final client = ref.read(heartyApiClientProvider);
    state = const AsyncLoading();
    try {
      await client.triggerAnalysis();
      await refresh();
    } catch (e, st) {
      final cached = await ref.read(localTrendsDaoProvider).read();
      state = cached != null ? AsyncData(cached) : AsyncError(e, st);
    }
  }

  Future<void> setDays(int days) => refresh();
}

final trendsProvider =
    AsyncNotifierProvider<TrendsNotifier, TrendsData>(TrendsNotifier.new);
