/// A single food item identified by the AI Vision food-plate pipeline.
///
/// Matches the backend `food_plate_vision` result shape:
/// `{"name": str, "portion": str?, "confidence": float?}`.
class IdentifiedFood {
  final String name;
  final String? portion;
  final double? confidence;

  const IdentifiedFood({
    required this.name,
    this.portion,
    this.confidence,
  });

  factory IdentifiedFood.fromJson(Map<String, dynamic> json) => IdentifiedFood(
        name: (json['name'] as String?) ?? '',
        portion: json['portion'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );
}

/// Typed view of `GET /api/photos/{id}/status`.
///
/// `status` ∈ processing | complete | failed. When `complete`, the backend
/// `result` holds `{"foods": [...], "source": "..."}`; [foods] parses
/// `result["foods"]` (empty when `result` is null). When `failed`, [error]
/// carries the failure message. The raw [result] map is retained so non-food
/// photo types (barcode / nutrition label) can still read their own shapes.
class PhotoAnalysis {
  final String id;
  final String type;
  final String status;
  final List<IdentifiedFood> foods;
  final String? error;
  final Map<String, dynamic>? result;

  const PhotoAnalysis({
    required this.id,
    required this.type,
    required this.status,
    this.foods = const [],
    this.error,
    this.result,
  });

  bool get isComplete => status == 'complete';
  bool get isFailed => status == 'failed';

  factory PhotoAnalysis.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>?;
    final rawFoods = result?['foods'];
    final foods = rawFoods is List
        ? rawFoods
            .whereType<Map<String, dynamic>>()
            .map(IdentifiedFood.fromJson)
            .toList()
        : <IdentifiedFood>[];

    return PhotoAnalysis(
      id: json['id'] as String,
      type: (json['type'] as String?) ?? 'food_plate',
      status: json['status'] as String,
      foods: foods,
      error: json['error'] as String?,
      result: result,
    );
  }
}
