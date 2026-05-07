class MealLog {
  final String id;
  final String description;
  final String mealType;
  final List<String> foods;
  final DateTime loggedAt;
  final String? claudeNote;

  const MealLog({
    required this.id,
    required this.description,
    required this.mealType,
    required this.foods,
    required this.loggedAt,
    this.claudeNote,
  });

  factory MealLog.fromJson(Map<String, dynamic> json) {
    // The backend returns a list of FoodItem objects; flatten to names.
    final rawFoods = json['foods'];
    List<String> foodNames = [];
    if (rawFoods is List) {
      for (final item in rawFoods) {
        if (item is Map<String, dynamic>) {
          foodNames.add(item['name'] as String? ?? '');
        } else if (item is String) {
          foodNames.add(item);
        }
      }
    }

    return MealLog(
      id: json['id'] as String,
      description: json['description'] as String,
      mealType: (json['meal_type'] as String?) ?? 'other',
      foods: foodNames,
      loggedAt: DateTime.parse(json['logged_at'] as String),
      claudeNote: json['claude_note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'meal_type': mealType,
        'foods': foods,
        'logged_at': loggedAt.toIso8601String(),
        if (claudeNote != null) 'claude_note': claudeNote,
      };
}
