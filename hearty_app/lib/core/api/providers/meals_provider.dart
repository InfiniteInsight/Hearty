import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../offline/local_meal_dao.dart';
import '../models/meal_log.dart';

const _uuid = Uuid();

class MealsNotifier extends StreamNotifier<List<MealLog>> {
  @override
  Stream<List<MealLog>> build() {
    return ref.watch(localMealDaoProvider).watchToday();
  }

  Future<void> logMeal(String description, {String? mealType}) async {
    final dao = ref.read(localMealDaoProvider);
    await dao.insertLocal(
      localId: _uuid.v4(),
      description: description,
      mealType: mealType ?? 'other',
      foods: [],
      loggedAt: DateTime.now(),
    );
    ref.read(syncTriggerProvider).schedule();
  }
}

final mealsProvider =
    StreamNotifierProvider<MealsNotifier, List<MealLog>>(MealsNotifier.new);

/// Minimal interface the sync trigger exposes so providers don't import SyncService directly.
abstract class SyncTrigger {
  void schedule();
}

final syncTriggerProvider = Provider<SyncTrigger>((ref) {
  throw UnimplementedError('syncTriggerProvider must be overridden in ProviderScope');
});
