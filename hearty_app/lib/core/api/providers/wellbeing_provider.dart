import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearty_api_client.dart';
import '../models/wellbeing_log.dart';
import '../models/wellbeing_period.dart';

const _kAnalysisChannel = MethodChannel('com.hearty.app/analysis');

class WellbeingNotifier extends AsyncNotifier<List<WellbeingLog>> {
  @override
  Future<List<WellbeingLog>> build() async {
    final client = ref.watch(heartyApiClientProvider);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc();
    return client.fetchWellbeing(start: startOfDay, end: now.toUtc());
  }

  Future<void> logWellbeing({
    int? energy,
    int? mood,
    String? notes,
    WellbeingPeriod? period,
  }) async {
    final client = ref.read(heartyApiClientProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final newEntry = await client.logWellbeing(
        energy: energy,
        mood: mood,
        notes: notes,
        period: period,
      );
      // Signal native layer to enqueue idle analysis now that new data exists.
      _enqueueIdleAnalysis();
      final current = state.valueOrNull ?? [];
      return [newEntry, ...current];
    });
  }

  void _enqueueIdleAnalysis() {
    _kAnalysisChannel
        .invokeMethod<void>('enqueueIdleAnalysis')
        .ignore();
  }

  Future<void> updateWellbeing(
    String id, {
    int? energy,
    int? mood,
    String? notes,
    WellbeingPeriod? period,
  }) async {
    final client = ref.read(heartyApiClientProvider);
    final previous = state.valueOrNull ?? [];
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final updated = await client.updateWellbeing(
        id,
        energy: energy,
        mood: mood,
        notes: notes,
        period: period,
      );
      return previous.map((e) => e.id == id ? updated : e).toList();
    });
  }
}

final wellbeingProvider =
    AsyncNotifierProvider<WellbeingNotifier, List<WellbeingLog>>(
        WellbeingNotifier.new);
