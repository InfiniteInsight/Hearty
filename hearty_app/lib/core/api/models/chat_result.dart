class ChatResult {
  final String reply;
  final String? mealId;

  const ChatResult({required this.reply, this.mealId});

  factory ChatResult.fromJson(Map<String, dynamic> json) => ChatResult(
        reply: (json['reply'] as String?) ??
            (json['response'] as String?) ??
            (json['message'] as String?) ??
            '',
        mealId: json['meal_id'] as String?,
      );
}
