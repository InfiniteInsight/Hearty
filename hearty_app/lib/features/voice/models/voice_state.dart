enum VoiceStatus { idle, listening, thinking, responding, awaitingFollowUp }

class VoiceState {
  final VoiceStatus status;
  final String transcript;
  final String response;

  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.response = '',
  });

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    String? response,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        response: response ?? this.response,
      );
}
