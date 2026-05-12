import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearty_api_client.dart';
import '../models/symptom_log.dart';

class SymptomsNotifier extends AsyncNotifier<List<SymptomLog>> {
  @override
  Future<List<SymptomLog>> build() async {
    final client = ref.watch(heartyApiClientProvider);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc();
    return client.fetchSymptoms(start: startOfDay, end: now.toUtc());
  }

  Future<void> logSymptom(String description, {int? severity}) async {
    final client = ref.read(heartyApiClientProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final newSymptom = await client.logSymptom(
        description: description,
        severity: severity,
      );
      final current = state.valueOrNull ?? [];
      return [newSymptom, ...current];
    });
  }
}

final symptomsProvider =
    AsyncNotifierProvider<SymptomsNotifier, List<SymptomLog>>(
        SymptomsNotifier.new);
