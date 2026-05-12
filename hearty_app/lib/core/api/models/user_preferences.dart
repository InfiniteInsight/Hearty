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
  // Per-slot check-in preferences
  final bool morningCheckinEnabled;
  final int morningCheckinHour;
  final int morningCheckinMinute;
  final bool middayCheckinEnabled;
  final int middayCheckinHour;
  final int middayCheckinMinute;
  final bool eveningCheckinEnabled;
  final int eveningCheckinHour;
  final int eveningCheckinMinute;

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
    this.morningCheckinEnabled = true,
    this.morningCheckinHour = 8,
    this.morningCheckinMinute = 0,
    this.middayCheckinEnabled = true,
    this.middayCheckinHour = 13,
    this.middayCheckinMinute = 0,
    this.eveningCheckinEnabled = true,
    this.eveningCheckinHour = 20,
    this.eveningCheckinMinute = 0,
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
      morningCheckinEnabled: (json['morning_checkin_enabled'] as bool?) ?? true,
      morningCheckinHour: (json['morning_checkin_hour'] as int?) ?? 8,
      morningCheckinMinute: (json['morning_checkin_minute'] as int?) ?? 0,
      middayCheckinEnabled: (json['midday_checkin_enabled'] as bool?) ?? true,
      middayCheckinHour: (json['midday_checkin_hour'] as int?) ?? 13,
      middayCheckinMinute: (json['midday_checkin_minute'] as int?) ?? 0,
      eveningCheckinEnabled: (json['evening_checkin_enabled'] as bool?) ?? true,
      eveningCheckinHour: (json['evening_checkin_hour'] as int?) ?? 20,
      eveningCheckinMinute: (json['evening_checkin_minute'] as int?) ?? 0,
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
        'morning_checkin_enabled': morningCheckinEnabled,
        'morning_checkin_hour': morningCheckinHour,
        'morning_checkin_minute': morningCheckinMinute,
        'midday_checkin_enabled': middayCheckinEnabled,
        'midday_checkin_hour': middayCheckinHour,
        'midday_checkin_minute': middayCheckinMinute,
        'evening_checkin_enabled': eveningCheckinEnabled,
        'evening_checkin_hour': eveningCheckinHour,
        'evening_checkin_minute': eveningCheckinMinute,
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
    bool? morningCheckinEnabled,
    int? morningCheckinHour,
    int? morningCheckinMinute,
    bool? middayCheckinEnabled,
    int? middayCheckinHour,
    int? middayCheckinMinute,
    bool? eveningCheckinEnabled,
    int? eveningCheckinHour,
    int? eveningCheckinMinute,
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
      morningCheckinEnabled: morningCheckinEnabled ?? this.morningCheckinEnabled,
      morningCheckinHour: morningCheckinHour ?? this.morningCheckinHour,
      morningCheckinMinute: morningCheckinMinute ?? this.morningCheckinMinute,
      middayCheckinEnabled: middayCheckinEnabled ?? this.middayCheckinEnabled,
      middayCheckinHour: middayCheckinHour ?? this.middayCheckinHour,
      middayCheckinMinute: middayCheckinMinute ?? this.middayCheckinMinute,
      eveningCheckinEnabled: eveningCheckinEnabled ?? this.eveningCheckinEnabled,
      eveningCheckinHour: eveningCheckinHour ?? this.eveningCheckinHour,
      eveningCheckinMinute: eveningCheckinMinute ?? this.eveningCheckinMinute,
    );
  }
}
