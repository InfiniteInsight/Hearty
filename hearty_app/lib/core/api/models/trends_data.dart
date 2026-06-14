class TrendsData {
  final List<SymptomFrequencyPoint> symptomFrequency;
  final List<FoodSignal> signals;
  final Map<String, int> mealTypeDistribution;
  final DateTime? analyzedAt;
  final List<ResolvedSignal> resolved;

  const TrendsData({
    required this.symptomFrequency,
    required this.signals,
    required this.mealTypeDistribution,
    this.analyzedAt,
    this.resolved = const [],
  });

  factory TrendsData.fromSignalsJson(Map<String, dynamic> json) {
    final signals = (json['signals'] as List<dynamic>? ?? [])
        .map((s) => FoodSignal.fromJson(s as Map<String, dynamic>))
        .toList();

    final analyzedAtStr = json['analyzed_at'] as String?;
    final analyzedAt =
        analyzedAtStr != null ? DateTime.tryParse(analyzedAtStr) : null;

    return TrendsData(
      symptomFrequency: [],
      signals: signals,
      mealTypeDistribution: {},
      analyzedAt: analyzedAt,
      resolved: ((json['resolved'] as List<dynamic>?) ?? const [])
          .map((e) => ResolvedSignal.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'signals': signals.map((s) => s.toJson()).toList(),
        'analyzed_at': analyzedAt?.toIso8601String(),
        // Persisted so the 'No longer flagging' section survives an offline reload.
        'resolved': resolved.map((r) => r.toJson()).toList(),
      };
}

// ── Resolved (no longer flagging) signals ────────────────────────────────────

class ResolvedSignal {
  final String category;
  final int lastYear;
  final double strength;
  final String status; // 'resolved' | 'potentially_resolved'

  const ResolvedSignal({
    required this.category,
    required this.lastYear,
    required this.strength,
    required this.status,
  });

  factory ResolvedSignal.fromJson(Map<String, dynamic> json) => ResolvedSignal(
        category: (json['category'] as String?) ?? '',
        lastYear: (json['last_year'] as num?)?.toInt() ?? 0,
        strength: (json['strength'] as num?)?.toDouble() ?? 0.0,
        status: (json['status'] as String?) ?? 'potentially_resolved',
      );

  Map<String, dynamic> toJson() => {
        'category': category,
        'last_year': lastYear,
        'strength': strength,
        'status': status,
      };
}

// ── Signal models (Plan 11) ──────────────────────────────────────────────────

class SignalChannel {
  final String outcomeType;
  final String outcomeName;
  final String direction;
  final int? peakWindowMinutes;
  final String? mealSlot;
  final double? relativeRisk;
  final double? scoreDelta;
  final int evidenceCount;

  const SignalChannel({
    required this.outcomeType,
    required this.outcomeName,
    required this.direction,
    this.peakWindowMinutes,
    this.mealSlot,
    this.relativeRisk,
    this.scoreDelta,
    required this.evidenceCount,
  });

  factory SignalChannel.fromJson(Map<String, dynamic> json) {
    return SignalChannel(
      outcomeType: json['outcome_type'] as String,
      outcomeName: json['outcome_name'] as String,
      direction: json['direction'] as String,
      peakWindowMinutes: json['peak_window_minutes'] as int?,
      mealSlot: json['meal_slot'] as String?,
      relativeRisk: (json['relative_risk'] as num?)?.toDouble(),
      scoreDelta: (json['score_delta'] as num?)?.toDouble(),
      evidenceCount: (json['evidence_count'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'outcome_type': outcomeType,
        'outcome_name': outcomeName,
        'direction': direction,
        'peak_window_minutes': peakWindowMinutes,
        'meal_slot': mealSlot,
        'relative_risk': relativeRisk,
        'score_delta': scoreDelta,
        'evidence_count': evidenceCount,
      };
}

class FoodSignal {
  final String category;
  final double unifiedScore;
  final List<SignalChannel> channels;
  final bool convergent;
  final List<int> yearsSeen;
  final bool recurring;
  final bool isNew;
  final Map<String, double> strengthByYear;

  const FoodSignal({
    required this.category,
    required this.unifiedScore,
    required this.channels,
    required this.convergent,
    this.yearsSeen = const [],
    this.recurring = false,
    this.isNew = false,
    this.strengthByYear = const {},
  });

  factory FoodSignal.fromJson(Map<String, dynamic> json) {
    return FoodSignal(
      category: json['category'] as String,
      unifiedScore: (json['unified_score'] as num).toDouble(),
      channels: (json['channels'] as List<dynamic>)
          .map((c) => SignalChannel.fromJson(c as Map<String, dynamic>))
          .toList(),
      convergent: json['convergent'] as bool? ?? false,
      yearsSeen: ((json['years_seen'] as List<dynamic>?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      recurring: (json['recurring'] as bool?) ?? false,
      isNew: (json['is_new'] as bool?) ?? false,
      strengthByYear: ((json['strength_by_year'] as Map<dynamic, dynamic>?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'unified_score': unifiedScore,
        'channels': channels.map((c) => c.toJson()).toList(),
        'convergent': convergent,
        // Persistence fields included so the offline cache round-trip
        // (toJson -> fromSignalsJson) keeps badges + sparkline.
        'years_seen': yearsSeen,
        'recurring': recurring,
        'is_new': isNew,
        'strength_by_year': strengthByYear,
      };
}

// ── Chart data models ────────────────────────────────────────────────────────

class SymptomFrequencyPoint {
  final DateTime date;
  final String symptomType;
  final int count;

  const SymptomFrequencyPoint({
    required this.date,
    required this.symptomType,
    required this.count,
  });

  factory SymptomFrequencyPoint.fromJson(Map<String, dynamic> json) {
    return SymptomFrequencyPoint(
      date: DateTime.parse(json['date'] as String),
      symptomType: json['symptom_type'] as String,
      count: json['count'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'symptom_type': symptomType,
        'count': count,
      };
}
