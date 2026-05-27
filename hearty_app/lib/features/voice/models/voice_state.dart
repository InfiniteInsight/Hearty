enum VoiceStatus { idle, listening, thinking, responding, awaitingFollowUp }

class VoiceState {
  final VoiceStatus status;
  final String transcript;
  final String response;
  final String? pendingMealId;
  final List<Map<String, String>> history;

  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.response = '',
    this.pendingMealId,
    this.history = const [],
  });

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    String? response,
    String? pendingMealId,
    List<Map<String, String>>? history,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        response: response ?? this.response,
        pendingMealId: pendingMealId ?? this.pendingMealId,
        history: history ?? this.history,
      );
}
