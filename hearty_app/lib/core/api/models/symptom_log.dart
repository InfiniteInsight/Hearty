import '../../offline/offline_database.dart';

class SymptomLog {
  final String id;
  final String description;
  final int severity;
  final int? onsetMinutes;
  final String? linkedMealId;
  final DateTime loggedAt;

  const SymptomLog({
    required this.id,
    required this.description,
    required this.severity,
    this.onsetMinutes,
    this.linkedMealId,
    required this.loggedAt,
  });

  factory SymptomLog.fromLocal(LocalSymptom row) {
    return SymptomLog(
      id: row.serverId ?? row.id,
      description: row.description,
      severity: row.severity,
      linkedMealId: row.linkedMealId,
      loggedAt: DateTime.fromMillisecondsSinceEpoch(row.loggedAt),
    );
  }

  factory SymptomLog.fromJson(Map<String, dynamic> json) {
    return SymptomLog(
      id: json['id'] as String,
      description: (json['symptom_type'] as String?) ??
          (json['raw_description'] as String?) ??
          '',
      severity: (json['severity'] as int?) ?? 1,
      onsetMinutes: json['onset_minutes'] as int?,
      linkedMealId: json['meal_id'] as String?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'symptom_type': description,
        'severity': severity,
        if (onsetMinutes != null) 'onset_minutes': onsetMinutes,
        if (linkedMealId != null) 'meal_id': linkedMealId,
        'logged_at': loggedAt.toIso8601String(),
      };
}
