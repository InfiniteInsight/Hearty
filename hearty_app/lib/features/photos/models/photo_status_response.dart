class PhotoStatusResponse {
  final String id;
  final String type;
  final String status; // 'pending' | 'complete' | 'error'
  final Map<String, dynamic>? result;
  final String? error;

  const PhotoStatusResponse({
    required this.id,
    required this.type,
    required this.status,
    this.result,
    this.error,
  });

  /// Returns the list of food items from the processing result, if available.
  List<Map<String, dynamic>> get foods {
    final raw = result?['foods'];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  /// Returns any top-level allergen warnings from the processing result.
  /// Field name assumed from spec description; backend may use a different key.
  List<String> get allergenWarnings {
    final raw = result?['allergen_warnings'];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return [];
  }

  factory PhotoStatusResponse.fromJson(Map<String, dynamic> json) =>
      PhotoStatusResponse(
        id: json['id'] as String,
        type: json['type'] as String,
        status: json['status'] as String,
        result: json['result'] as Map<String, dynamic>?,
        error: json['error'] as String?,
      );
}
