class WellbeingLog {
  final String id;
  final int energy;
  final int mood;
  final String? notes;
  final DateTime loggedAt;

  const WellbeingLog({
    required this.id,
    required this.energy,
    required this.mood,
    this.notes,
    required this.loggedAt,
  });

  factory WellbeingLog.fromJson(Map<String, dynamic> json) {
    return WellbeingLog(
      id: json['id'] as String,
      // Backend uses energy_level; task spec uses energy.
      energy: (json['energy_level'] as int?) ?? (json['energy'] as int?) ?? 3,
      mood: (json['mood'] as int?) ?? 3,
      notes: json['notes'] as String?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'energy_level': energy,
        'mood': mood,
        if (notes != null) 'notes': notes,
        'logged_at': loggedAt.toIso8601String(),
      };
}
