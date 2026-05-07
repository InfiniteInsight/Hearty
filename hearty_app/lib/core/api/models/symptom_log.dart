class SymptomLog {
  final String id;
  final String description;
  final int severity;
  final String? linkedMealId;
  final DateTime loggedAt;

  const SymptomLog({
    required this.id,
    required this.description,
    required this.severity,
    this.linkedMealId,
    required this.loggedAt,
  });

  factory SymptomLog.fromJson(Map<String, dynamic> json) {
    return SymptomLog(
      id: json['id'] as String,
      // Backend uses symptom_type; fall back to raw_description if available.
      description: (json['symptom_type'] as String?) ??
          (json['raw_description'] as String?) ??
          '',
      severity: (json['severity'] as int?) ?? 1,
      linkedMealId: json['meal_id'] as String?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'symptom_type': description,
        'severity': severity,
        if (linkedMealId != null) 'meal_id': linkedMealId,
        'logged_at': loggedAt.toIso8601String(),
      };
}
