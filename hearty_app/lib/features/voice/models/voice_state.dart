enum VoiceStatus { idle, listening, thinking, responding, awaitingFollowUp }

class VoiceState {
  final VoiceStatus status;
  final String transcript;
  final String response;
  final String? pendingMealId;
  final String? originalTranscript;

  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.response = '',
    this.pendingMealId,
    this.originalTranscript,
  });

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    String? response,
    String? pendingMealId,
    String? originalTranscript,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        response: response ?? this.response,
        pendingMealId: pendingMealId ?? this.pendingMealId,
        originalTranscript: originalTranscript ?? this.originalTranscript,
      );
}
