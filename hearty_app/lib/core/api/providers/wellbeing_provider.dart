// lib/core/api/providers/wellbeing_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../offline/local_wellbeing_dao.dart';
import '../models/wellbeing_log.dart';
import '../models/wellbeing_period.dart';
import 'meals_provider.dart' show syncTriggerProvider;

const _uuid = Uuid();

class WellbeingNotifier extends StreamNotifier<List<WellbeingLog>> {
  @override
  Stream<List<WellbeingLog>> build() {
    return ref.watch(localWellbeingDaoProvider).watchToday();
  }

  Future<void> logWellbeing({
    int? energy,
    int? mood,
    String? notes,
    WellbeingPeriod? period,
  }) async {
    final dao = ref.read(localWellbeingDaoProvider);
    await dao.insertLocal(
      localId: _uuid.v4(),
      energy: energy ?? 3,
      mood: mood ?? 3,
      notes: notes,
      period: period?.name,
      loggedAt: DateTime.now(),
    );
    ref.read(syncTriggerProvider).schedule();
  }

  Future<void> updateWellbeing(
    String id, {
    int? energy,
    int? mood,
    String? notes,
    WellbeingPeriod? period,
  }) async {
    final dao = ref.read(localWellbeingDaoProvider);
    await dao.updateLocal(id, energy: energy, mood: mood, notes: notes, period: period);
    ref.read(syncTriggerProvider).schedule();
  }
}

final wellbeingProvider =
    StreamNotifierProvider<WellbeingNotifier, List<WellbeingLog>>(
        WellbeingNotifier.new);
