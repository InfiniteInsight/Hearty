import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../offline/local_symptom_dao.dart';
import '../models/symptom_log.dart';
import 'meals_provider.dart' show syncTriggerProvider;

const _uuid = Uuid();

class SymptomsNotifier extends StreamNotifier<List<SymptomLog>> {
  @override
  Stream<List<SymptomLog>> build() {
    return ref.watch(localSymptomDaoProvider).watchToday();
  }

  Future<void> logSymptom(String description, {int? severity}) async {
    final dao = ref.read(localSymptomDaoProvider);
    await dao.insertLocal(
      localId: _uuid.v4(),
      description: description,
      severity: severity ?? 1,
      loggedAt: DateTime.now(),
    );
    ref.read(syncTriggerProvider).schedule();
  }
}

final symptomsProvider =
    StreamNotifierProvider<SymptomsNotifier, List<SymptomLog>>(
        SymptomsNotifier.new);
