import '../../core/api/models/checkin_gap.dart';

/// Composes the human-facing question shown for a check-in [gap].
///
/// Meal-anchored gaps (`symptom_gap` / `low_confidence`) are rendered with the
/// meal's name and a device-local time so the user knows exactly which meal is
/// being asked about — instead of the vague "that meal". Falls back to the
/// backend-supplied [CheckinGap.prompt] whenever the context needed to build a
/// specific question is missing (a meal with no foods, a missing time window, or
/// an unknown gap type the server may add later).
String checkinQuestionText(CheckinGap gap) {
  switch (gap.type) {
    case 'symptom_gap':
      final label = gap.mealLabel;
      if (label == null || label.isEmpty) return gap.prompt;
      final type = gap.mealType;
      final typePart = (type != null && type.isNotEmpty) ? ' — $type' : '';
      final timePart =
          gap.mealTime != null ? ', around ${_localClock(gap.mealTime!)}' : '';
      return 'How did your stomach feel after your $label$typePart$timePart?';

    case 'low_confidence':
      final food = gap.foodName;
      final time = gap.mealTime;
      if (food == null || food.isEmpty || time == null) return gap.prompt;
      final type = gap.mealType;
      final meal = (type != null && type.isNotEmpty) ? type : 'meal';
      return 'On your $meal around ${_localClock(time)}, '
          'I logged "$food" — did I get that right?';

    case 'missing_chunk':
      final start = _tryParse(gap.windowStart);
      final end = _tryParse(gap.windowEnd);
      if (start == null || end == null) return gap.prompt;
      return "I don't see anything logged between about "
          '${_localClock(start)} and ${_localClock(end)} — did you eat then?';

    default:
      return gap.prompt;
  }
}

DateTime? _tryParse(String? iso) =>
    iso == null ? null : DateTime.tryParse(iso);

/// Local-time clock like "12:30 PM". Hand-rolled to match the radial clock's
/// formatting — the app carries no `intl` dependency.
String _localClock(DateTime t) {
  final local = t.toLocal();
  final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final mm = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  return '$h12:$mm $ampm';
}
