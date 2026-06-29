import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../notifications/notification_service.dart';
import '../../offline/local_meal_dao.dart';
import '../models/meal_log.dart';
import 'preferences_provider.dart';

const _uuid = Uuid();

class MealsNotifier extends StreamNotifier<List<MealLog>> {
  @override
  Stream<List<MealLog>> build() {
    return ref.watch(localMealDaoProvider).watchToday();
  }

  Future<void> logMeal(
    String description, {
    String? mealType,
    List<String>? foods,
    String inputMethod = 'voice',
  }) async {
    final dao = ref.read(localMealDaoProvider);
    await dao.insertLocal(
      localId: _uuid.v4(),
      description: description,
      mealType: mealType ?? 'other',
      foods: foods ?? [],
      loggedAt: DateTime.now(),
    );
    ref.read(syncTriggerProvider).schedule();

    // Best-effort: scheduling the post-meal reminder must never break the log
    // flow. If it throws (e.g. exact-alarm/permission/platform edge cases), the
    // meal is already saved and the caller still shows the feeling follow-up —
    // a throw here previously propagated out of logMeal and skipped that sheet.
    final prefs = ref.read(preferencesProvider).valueOrNull;
    if (prefs != null && prefs.postMealNudgeEnabled) {
      try {
        await NotificationService.scheduleFollowUpNotification(
          prefs.nudgeDelayMinutes,
        );
      } catch (e) {
        debugPrint('Failed to schedule follow-up notification: $e');
      }
    }
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
