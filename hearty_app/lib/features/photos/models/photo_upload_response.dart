class PhotoUploadResponse {
  final String id;
  final String type;
  final String status;
  final String? mealId;
  final String message;

  const PhotoUploadResponse({
    required this.id,
    required this.type,
    required this.status,
    this.mealId,
    required this.message,
  });

  factory PhotoUploadResponse.fromJson(Map<String, dynamic> json) =>
      PhotoUploadResponse(
        id: json['id'] as String,
        type: json['type'] as String,
        status: json['status'] as String,
        mealId: json['meal_id'] as String?,
        message: json['message'] as String? ?? '',
      );
}
