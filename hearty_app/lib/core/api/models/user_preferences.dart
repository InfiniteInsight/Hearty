class UserPreferences {
  final List<String> allergens;
  final List<String> conditions;
  final List<String> dietaryProtocols;
  final List<String> medications;
  final int nudgeDelayMinutes;
  final bool postMealNudgeEnabled;
  final bool dailyCheckinEnabled;
  final bool weeklyDigestEnabled;
  final bool syncErrorAlertsEnabled;
  final bool wakeWordEnabled;
  final int dailyCheckinHour;
  final int dailyCheckinMinute;
  final String? fcmToken;

  const UserPreferences({
    this.allergens = const [],
    this.conditions = const [],
    this.dietaryProtocols = const [],
    this.medications = const [],
    this.nudgeDelayMinutes = 45,
    this.postMealNudgeEnabled = true,
    this.dailyCheckinEnabled = true,
    this.weeklyDigestEnabled = true,
    this.syncErrorAlertsEnabled = true,
    this.wakeWordEnabled = true,
    this.dailyCheckinHour = 8,
    this.dailyCheckinMinute = 0,
    this.fcmToken,
  });

  static List<String> _toStringList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      allergens: _toStringList(json['allergens']),
      conditions: _toStringList(json['conditions']),
      dietaryProtocols: _toStringList(json['dietary_protocols']),
      medications: _toStringList(json['medications']),
      nudgeDelayMinutes: (json['nudge_delay_minutes'] as int?) ?? 45,
      postMealNudgeEnabled:
          (json['post_meal_nudge_enabled'] as bool?) ?? true,
      dailyCheckinEnabled:
          (json['daily_checkin_enabled'] as bool?) ?? true,
      weeklyDigestEnabled:
          (json['weekly_digest_enabled'] as bool?) ?? true,
      syncErrorAlertsEnabled:
          (json['sync_error_alerts_enabled'] as bool?) ?? true,
      wakeWordEnabled: (json['wake_word_enabled'] as bool?) ?? true,
      dailyCheckinHour: (json['daily_checkin_hour'] as int?) ?? 8,
      dailyCheckinMinute: (json['daily_checkin_minute'] as int?) ?? 0,
      fcmToken: json['fcm_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'allergens': allergens,
        'conditions': conditions,
        'dietary_protocols': dietaryProtocols,
        'medications': medications,
        'nudge_delay_minutes': nudgeDelayMinutes,
        'post_meal_nudge_enabled': postMealNudgeEnabled,
        'daily_checkin_enabled': dailyCheckinEnabled,
        'weekly_digest_enabled': weeklyDigestEnabled,
        'sync_error_alerts_enabled': syncErrorAlertsEnabled,
        'wake_word_enabled': wakeWordEnabled,
        'daily_checkin_hour': dailyCheckinHour,
        'daily_checkin_minute': dailyCheckinMinute,
        if (fcmToken != null) 'fcm_token': fcmToken,
      };

  UserPreferences copyWith({
    List<String>? allergens,
    List<String>? conditions,
    List<String>? dietaryProtocols,
    List<String>? medications,
    int? nudgeDelayMinutes,
    bool? postMealNudgeEnabled,
    bool? dailyCheckinEnabled,
    bool? weeklyDigestEnabled,
    bool? syncErrorAlertsEnabled,
    bool? wakeWordEnabled,
    int? dailyCheckinHour,
    int? dailyCheckinMinute,
    String? fcmToken,
  }) {
    return UserPreferences(
      allergens: allergens ?? this.allergens,
      conditions: conditions ?? this.conditions,
      dietaryProtocols: dietaryProtocols ?? this.dietaryProtocols,
      medications: medications ?? this.medications,
      nudgeDelayMinutes: nudgeDelayMinutes ?? this.nudgeDelayMinutes,
      postMealNudgeEnabled: postMealNudgeEnabled ?? this.postMealNudgeEnabled,
      dailyCheckinEnabled: dailyCheckinEnabled ?? this.dailyCheckinEnabled,
      weeklyDigestEnabled: weeklyDigestEnabled ?? this.weeklyDigestEnabled,
      syncErrorAlertsEnabled:
          syncErrorAlertsEnabled ?? this.syncErrorAlertsEnabled,
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      dailyCheckinHour: dailyCheckinHour ?? this.dailyCheckinHour,
      dailyCheckinMinute: dailyCheckinMinute ?? this.dailyCheckinMinute,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }
}
