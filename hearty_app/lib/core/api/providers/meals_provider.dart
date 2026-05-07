import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hearty_api_client.dart';
import '../models/meal_log.dart';

class MealsNotifier extends AsyncNotifier<List<MealLog>> {
  @override
  Future<List<MealLog>> build() async {
    final client = ref.watch(heartyApiClientProvider);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return client.fetchMeals(start: startOfDay, end: now);
  }

  Future<void> logMeal(String description, {String? mealType}) async {
    final client = ref.read(heartyApiClientProvider);
    final previous = state.valueOrNull ?? [];
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final newMeal = await client.logMeal(
        description: description,
        mealType: mealType,
      );
      return [newMeal, ...previous];
    });
  }
}

final mealsProvider =
    AsyncNotifierProvider<MealsNotifier, List<MealLog>>(MealsNotifier.new);
