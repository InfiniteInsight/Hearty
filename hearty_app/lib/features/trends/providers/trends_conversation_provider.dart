import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/models/experiment.dart';
import '../../../core/api/models/trends_turn.dart';

/// Lifecycle of the monthly trends conversation:
/// loading → active (a back-and-forth chat) → closed. [error] is reached if a
/// turn request throws. `isClosing` is a flag *within* [active] (the assistant
/// thinks it's wrapped up); the conversation only becomes [closed] when the user
/// explicitly ends it via [close].
enum TrendsConvoPhase { loading, active, closed, error }

/// Immutable snapshot of the trends conversation. Mirrors the repo's
/// const-ctor + [copyWith] state convention (see CheckinState).
class TrendsConvoState {
  final TrendsConvoPhase phase;

  /// Full transcript sent to the API: [{'role','content'}].
  final List<Map<String, String>> history;

  /// Latest assistant reply (shown prominently).
  final String currentReply;

  /// When non-null, a confirm/dismiss chip is shown for this proposed verdict.
  final ProposedVerdict? pendingVerdict;

  /// When non-null, a confirm chip is shown for this proposed experiment.
  final ProposedExperiment? pendingExperiment;

  /// The assistant considers the conversation wrapped up (still [active]).
  final bool isClosing;

  /// A turn/verdict request is in flight; inputs are disabled.
  final bool busy;

  const TrendsConvoState({
    this.phase = TrendsConvoPhase.loading,
    this.history = const [],
    this.currentReply = '',
    this.pendingVerdict,
    this.pendingExperiment,
    this.isClosing = false,
    this.busy = false,
  });

  TrendsConvoState copyWith({
    TrendsConvoPhase? phase,
    List<Map<String, String>>? history,
    String? currentReply,
    bool? isClosing,
    bool? busy,
  }) =>
      TrendsConvoState(
        phase: phase ?? this.phase,
        history: history ?? this.history,
        currentReply: currentReply ?? this.currentReply,
        // pendingVerdict/pendingExperiment are intentionally NOT copyWith params
        // — clearing one to null is a real state (resolved/dismissed), which a
        // `?? this` guard would swallow. Use [_withVerdict]/[_withExperiment].
        pendingVerdict: pendingVerdict,
        pendingExperiment: pendingExperiment,
        isClosing: isClosing ?? this.isClosing,
        busy: busy ?? this.busy,
      );

  /// copyWith variant that can set OR clear [pendingVerdict].
  TrendsConvoState _withVerdict(ProposedVerdict? verdict) => TrendsConvoState(
        phase: phase,
        history: history,
        currentReply: currentReply,
        pendingVerdict: verdict,
        pendingExperiment: pendingExperiment,
        isClosing: isClosing,
        busy: busy,
      );

  /// copyWith variant that can set OR clear [pendingExperiment].
  TrendsConvoState _withExperiment(ProposedExperiment? experiment) =>
      TrendsConvoState(
        phase: phase,
        history: history,
        currentReply: currentReply,
        pendingVerdict: pendingVerdict,
        pendingExperiment: experiment,
        isClosing: isClosing,
        busy: busy,
      );
}

/// Drives the monthly trends conversation: opens with an assistant turn, relays
/// the user's text replies, surfaces proposed verdicts for explicit confirmation
/// (never auto-submitted), and lets the user end the conversation.
///
/// Pure state logic — no UI, no voice. The API client is injected so tests can
/// pass a fake; the provider wires in the real one.
class TrendsConversationController extends StateNotifier<TrendsConvoState> {
  TrendsConversationController(this._api) : super(const TrendsConvoState());

  final HeartyApiClient _api;

  /// Opens the conversation with the assistant's first turn.
  Future<void> start() async {
    state = const TrendsConvoState(phase: TrendsConvoPhase.loading);
    try {
      final turn = await _api.trendsConversation(const []);
      state = TrendsConvoState(
        phase: TrendsConvoPhase.active,
        history: [
          {'role': 'assistant', 'content': turn.reply},
        ],
        currentReply: turn.reply,
        pendingVerdict: turn.proposedVerdict,
        pendingExperiment: turn.proposedExperiment,
        isClosing: turn.isClosing,
      );
    } catch (_) {
      state = const TrendsConvoState(phase: TrendsConvoPhase.error);
    }
  }

  /// Sends the user's [text] reply and fetches the next assistant turn.
  /// Blank input is ignored. On error → [TrendsConvoPhase.error].
  Future<void> sendUserTurn(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.busy) return;

    // Build the next history explicitly and send THAT — never read
    // state.history across the await (it may include the user turn or not).
    final next = [
      ...state.history,
      {'role': 'user', 'content': trimmed},
    ];
    state = state.copyWith(history: next, busy: true);

    try {
      final turn = await _api.trendsConversation(next);
      state = TrendsConvoState(
        phase: TrendsConvoPhase.active,
        history: [
          ...next,
          {'role': 'assistant', 'content': turn.reply},
        ],
        currentReply: turn.reply,
        pendingVerdict: turn.proposedVerdict,
        pendingExperiment: turn.proposedExperiment,
        isClosing: turn.isClosing,
        busy: false,
      );
    } catch (_) {
      state = const TrendsConvoState(phase: TrendsConvoPhase.error);
    }
  }

  /// Submits the pending verdict (the only path that ever records one), then
  /// clears it. No-op if there's nothing pending or a request is in flight.
  Future<void> confirmVerdict() async {
    final verdict = state.pendingVerdict;
    if (verdict == null || state.busy) return;
    state = state.copyWith(busy: true);
    try {
      await _api.submitSignalVerdict(
        category: verdict.category,
        outcomeType: verdict.outcomeType,
        outcomeName: verdict.outcomeName,
        verdict: verdict.verdict,
      );
      state = state.copyWith(busy: false)._withVerdict(null);
    } catch (_) {
      state = const TrendsConvoState(phase: TrendsConvoPhase.error);
    }
  }

  /// Starts the pending experiment (the only path that ever creates one), then
  /// clears it. No-op if there's nothing pending or a request is in flight.
  Future<void> startExperiment() async {
    final experiment = state.pendingExperiment;
    if (experiment == null || state.busy) return;
    state = state.copyWith(busy: true);
    try {
      await _api.createExperiment(
        category: experiment.category,
        outcomeType: experiment.outcomeType,
        outcomeName: experiment.outcomeName,
      );
      state = state.copyWith(busy: false)._withExperiment(null);
    } catch (_) {
      state = const TrendsConvoState(phase: TrendsConvoPhase.error);
    }
  }

  /// Dismisses the pending verdict WITHOUT recording it.
  void dismissVerdict() {
    if (state.pendingVerdict == null) return;
    state = state._withVerdict(null);
  }

  /// Ends the conversation (user-initiated).
  void close() {
    state = state.copyWith(phase: TrendsConvoPhase.closed);
  }
}

/// autoDispose so each visit to the trends conversation starts fresh.
final trendsConversationProvider = StateNotifierProvider.autoDispose<
    TrendsConversationController, TrendsConvoState>(
  (ref) => TrendsConversationController(ref.read(heartyApiClientProvider)),
);
