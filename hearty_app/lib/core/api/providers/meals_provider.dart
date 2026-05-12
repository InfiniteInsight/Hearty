import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearty_api_client.dart';
import '../models/meal_log.dart';

const _kAnalysisChannel = MethodChannel('com.hearty.app/analysis');

class MealsNotifier extends AsyncNotifier<List<MealLog>> {
  @override
  Future<List<MealLog>> build() async {
    final client = ref.watch(heartyApiClientProvider);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc();
    return client.fetchMeals(start: startOfDay, end: now.toUtc());
  }

  Future<void> logMeal(String description, {String? mealType}) async {
    final client = ref.read(heartyApiClientProvider);
    final previous = state.valueOrNull ?? [];
    state = const AsyncLoading();
    final next = await AsyncValue.guard(() async {
      final newMeal = await client.logMeal(
        description: description,
        mealType: mealType,
      );
      // Signal native layer to enqueue idle analysis now that new data exists.
      _enqueueIdleAnalysis();
      return [newMeal, ...previous];
    });
    // Preserve previous data on error so chips don't disappear.
    if (next is AsyncError<List<MealLog>>) {
      state = AsyncError<List<MealLog>>(next.error, next.stackTrace)
          .copyWithPrevious(AsyncData(previous));
    } else {
      state = next;
    }
  }

  void _enqueueIdleAnalysis() {
    _kAnalysisChannel
        .invokeMethod<void>('enqueueIdleAnalysis')
        .ignore(); // best-effort; never throws to caller
  }
}

final mealsProvider =
    AsyncNotifierProvider<MealsNotifier, List<MealLog>>(MealsNotifier.new);
