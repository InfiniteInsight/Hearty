import '../../offline/offline_database.dart';
import 'wellbeing_period.dart';

class WellbeingLog {
  final String id;
  final int energy;
  final int mood;
  final String? notes;
  final DateTime loggedAt;
  final WellbeingPeriod? period;

  const WellbeingLog({
    required this.id,
    required this.energy,
    required this.mood,
    this.notes,
    required this.loggedAt,
    this.period,
  });

  factory WellbeingLog.fromLocal(LocalWellbeingData row) {
    return WellbeingLog(
      id: row.id,
      energy: row.energy,
      mood: row.mood,
      notes: row.notes,
      loggedAt: DateTime.fromMillisecondsSinceEpoch(row.loggedAt),
      period: switch (row.period) {
        'morning' => WellbeingPeriod.morning,
        'midday' => WellbeingPeriod.midday,
        'evening' => WellbeingPeriod.evening,
        _ => null,
      },
    );
  }

  factory WellbeingLog.fromJson(Map<String, dynamic> json) {
    return WellbeingLog(
      id: json['id'] as String,
      energy: (json['energy_level'] as int?) ?? (json['energy'] as int?) ?? 3,
      mood: (json['mood'] as int?) ?? 3,
      notes: json['notes'] as String?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
      period: switch (json['period'] as String?) {
        'morning' => WellbeingPeriod.morning,
        'midday' => WellbeingPeriod.midday,
        'evening' => WellbeingPeriod.evening,
        _ => null,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'energy_level': energy,
        'mood': mood,
        if (notes != null) 'notes': notes,
        'logged_at': loggedAt.toIso8601String(),
        if (period != null) 'period': period!.name,
      };
}
