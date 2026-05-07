class TrendsData {
  final List<SymptomFrequencyPoint> symptomFrequency;
  final List<TriggerFood> topTriggerFoods;
  final List<WellbeingPoint> wellbeingTrend;
  final Map<String, int> mealTypeDistribution;

  const TrendsData({
    required this.symptomFrequency,
    required this.topTriggerFoods,
    required this.wellbeingTrend,
    required this.mealTypeDistribution,
  });

  factory TrendsData.fromJson(Map<String, dynamic> json) {
    // Backend returns TrendsResponse shape with triggers list.
    final triggers = (json['triggers'] as List<dynamic>? ?? [])
        .map((t) => TriggerFood.fromJson(t as Map<String, dynamic>))
        .toList();

    final symptomFreq = (json['symptom_frequency'] as List<dynamic>? ?? [])
        .map((p) => SymptomFrequencyPoint.fromJson(p as Map<String, dynamic>))
        .toList();

    final wellbeing = (json['wellbeing_trend'] as List<dynamic>? ?? [])
        .map((p) => WellbeingPoint.fromJson(p as Map<String, dynamic>))
        .toList();

    final mealDist = <String, int>{};
    final rawDist = json['meal_type_distribution'] as Map<String, dynamic>?;
    rawDist?.forEach((k, v) => mealDist[k] = v as int);

    return TrendsData(
      symptomFrequency: symptomFreq,
      topTriggerFoods: triggers,
      wellbeingTrend: wellbeing,
      mealTypeDistribution: mealDist,
    );
  }

  Map<String, dynamic> toJson() => {
        'symptom_frequency':
            symptomFrequency.map((p) => p.toJson()).toList(),
        'top_trigger_foods': topTriggerFoods.map((t) => t.toJson()).toList(),
        'wellbeing_trend': wellbeingTrend.map((p) => p.toJson()).toList(),
        'meal_type_distribution': mealTypeDistribution,
      };
}

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

class TriggerFood {
  final String food;
  final double confidenceScore;

  const TriggerFood({required this.food, required this.confidenceScore});

  factory TriggerFood.fromJson(Map<String, dynamic> json) {
    return TriggerFood(
      // Backend uses food_name
      food: (json['food_name'] as String?) ?? (json['food'] as String?) ?? '',
      confidenceScore:
          ((json['confidence_score'] as num?) ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'food': food,
        'confidence_score': confidenceScore,
      };
}

class WellbeingPoint {
  final DateTime date;
  final double energy;
  final double mood;

  const WellbeingPoint({
    required this.date,
    required this.energy,
    required this.mood,
  });

  factory WellbeingPoint.fromJson(Map<String, dynamic> json) {
    return WellbeingPoint(
      date: DateTime.parse(json['date'] as String),
      energy: ((json['energy'] as num?) ?? 0.0).toDouble(),
      mood: ((json['mood'] as num?) ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'energy': energy,
        'mood': mood,
      };
}
