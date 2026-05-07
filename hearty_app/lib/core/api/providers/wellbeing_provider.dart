import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearty_api_client.dart';
import '../models/wellbeing_log.dart';

class WellbeingNotifier extends AsyncNotifier<List<WellbeingLog>> {
  @override
  Future<List<WellbeingLog>> build() async {
    final client = ref.read(heartyApiClientProvider);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return client.fetchWellbeing(start: startOfDay, end: now);
  }

  Future<void> logWellbeing({int? energy, int? mood, String? notes}) async {
    final client = ref.read(heartyApiClientProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final newEntry = await client.logWellbeing(
        energy: energy,
        mood: mood,
        notes: notes,
      );
      final current = state.valueOrNull ?? [];
      return [newEntry, ...current];
    });
  }
}

final wellbeingProvider =
    AsyncNotifierProvider<WellbeingNotifier, List<WellbeingLog>>(
        WellbeingNotifier.new);
