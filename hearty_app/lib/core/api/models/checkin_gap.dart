/// A single daily-check-in gap surfaced by the backend.
///
/// Mirrors one entry of the `gaps` array from `GET /api/checkin/gaps`. The
/// [type] is kept as a plain string (`symptom_gap` | `low_confidence` |
/// `missing_chunk`) to match the backend contract without coupling the client
/// to a closed enum the server may extend.
class CheckinGap {
  final String type;
  final String prompt;
  final String? mealId;
  final String? foodName;
  final String? windowStart;
  final String? windowEnd;

  const CheckinGap({
    required this.type,
    required this.prompt,
    this.mealId,
    this.foodName,
    this.windowStart,
    this.windowEnd,
  });

  factory CheckinGap.fromJson(Map<String, dynamic> json) {
    return CheckinGap(
      type: json['type'] as String,
      prompt: json['prompt'] as String,
      mealId: json['meal_id'] as String?,
      foodName: json['food_name'] as String?,
      windowStart: json['window_start'] as String?,
      windowEnd: json['window_end'] as String?,
    );
  }
}

/// Compound result of `GET /api/checkin/gaps` — the target day, whether the
/// check-in window has [expired], and the list of outstanding [gaps].
class CheckinGapsResult {
  final String targetDate;
  final bool expired;
  final List<CheckinGap> gaps;

  const CheckinGapsResult({
    required this.targetDate,
    required this.expired,
    required this.gaps,
  });

  factory CheckinGapsResult.fromJson(Map<String, dynamic> json) {
    final rawGaps = json['gaps'] as List<dynamic>? ?? [];
    return CheckinGapsResult(
      targetDate: json['target_date'] as String? ?? '',
      expired: json['expired'] as bool? ?? false,
      gaps: rawGaps
          .map((g) => CheckinGap.fromJson(g as Map<String, dynamic>))
          .toList(),
    );
  }
}
