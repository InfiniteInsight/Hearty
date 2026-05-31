enum VoiceStatus { idle, listening, thinking, responding, awaitingFollowUp }

/// Sub-phase of the follow-up microphone, used to drive the overlay between
/// the orientation delay, the active listening session, and the idle
/// (tap-to-talk) state. `none` means not in the follow-up mic flow.
enum MicPhase { none, preparing, listening, paused }

class VoiceState {
  final VoiceStatus status;
  final String transcript;
  final String response;
  final String? pendingMealId;
  final List<Map<String, String>> history;
  final MicPhase micPhase;

  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.response = '',
    this.pendingMealId,
    this.history = const [],
    this.micPhase = MicPhase.none,
  });

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    String? response,
    String? pendingMealId,
    List<Map<String, String>>? history,
    MicPhase? micPhase,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        response: response ?? this.response,
        pendingMealId: pendingMealId ?? this.pendingMealId,
        history: history ?? this.history,
        micPhase: micPhase ?? this.micPhase,
      );
}
