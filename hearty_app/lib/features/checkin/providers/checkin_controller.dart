import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/models/checkin_gap.dart';

/// Lifecycle of a daily check-in session:
/// loading → preview (user chooses which gaps to skip) → cycling (one gap at a
/// time) → done. [error] is terminal and only reached if the initial gap fetch
/// throws.
enum CheckinPhase { loading, preview, cycling, done, error }

/// Immutable snapshot of the check-in flow. Mirrors the repo's
/// const-ctor + [copyWith] state convention (see VoiceState).
class CheckinState {
  final CheckinPhase phase;

  /// Gaps in backend order (A symptom → C low-confidence → D missing-chunk).
  final List<CheckinGap> gaps;

  /// Indices the user toggled off during [CheckinPhase.preview].
  final Set<int> skipped;

  /// Index of the gap being shown during [CheckinPhase.cycling].
  final int index;

  /// Reviewed day as `YYYY-MM-DD`.
  final String targetDate;

  /// True when the backend reported the check-in window has closed.
  final bool expired;

  const CheckinState({
    this.phase = CheckinPhase.loading,
    this.gaps = const [],
    this.skipped = const {},
    this.index = 0,
    this.targetDate = '',
    this.expired = false,
  });

  CheckinState copyWith({
    CheckinPhase? phase,
    List<CheckinGap>? gaps,
    Set<int>? skipped,
    int? index,
    String? targetDate,
    bool? expired,
  }) =>
      CheckinState(
        phase: phase ?? this.phase,
        gaps: gaps ?? this.gaps,
        skipped: skipped ?? this.skipped,
        index: index ?? this.index,
        targetDate: targetDate ?? this.targetDate,
        expired: expired ?? this.expired,
      );

  /// The gap currently under review, or null when not cycling / out of range.
  CheckinGap? get current =>
      (phase == CheckinPhase.cycling && index < gaps.length)
          ? gaps[index]
          : null;

  /// Count of not-yet-visited, non-skipped gaps from [index] onward (inclusive).
  int get remainingCount {
    var count = 0;
    for (var i = index; i < gaps.length; i++) {
      if (!skipped.contains(i)) count++;
    }
    return count;
  }
}

/// Orchestrates a daily check-in: fetches the gap queue, lets the user skip
/// gaps in a preview step, then walks the remaining gaps one at a time,
/// dispatching the right resolve call per gap [type] and advancing the queue.
///
/// Pure state logic — no UI, no voice. The API client is injected so tests can
/// pass a fake; the provider wires in the real one.
class CheckinController extends StateNotifier<CheckinState> {
  CheckinController(this._api, {required DateTime date})
      : _date = date,
        super(CheckinState(targetDate: _ymd(date)));

  final HeartyApiClient _api;
  final DateTime _date;

  /// Reviewed day as `YYYY-MM-DD`.
  String get targetDate => state.targetDate;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Fetches the gap queue for the target day.
  ///
  /// - expired window → [CheckinPhase.done] (expired, empty).
  /// - gaps present → [CheckinPhase.preview].
  /// - no gaps (not expired) → [CheckinPhase.done] (nothing to review).
  /// - fetch throws → [CheckinPhase.error].
  Future<void> load() async {
    try {
      final result = await _api.fetchCheckinGaps(_date);
      if (result.expired) {
        state = state.copyWith(
          phase: CheckinPhase.done,
          gaps: const [],
          expired: true,
          targetDate: result.targetDate,
        );
        return;
      }
      if (result.gaps.isEmpty) {
        state = state.copyWith(
          phase: CheckinPhase.done,
          gaps: const [],
          expired: false,
          targetDate: result.targetDate,
        );
        return;
      }
      state = state.copyWith(
        phase: CheckinPhase.preview,
        gaps: result.gaps,
        expired: false,
        targetDate: result.targetDate,
      );
    } catch (_) {
      state = state.copyWith(phase: CheckinPhase.error);
    }
  }

  /// Toggles gap [i] in/out of the skip set (preview only).
  void toggleSkip(int i) {
    if (state.phase != CheckinPhase.preview) return;
    final next = Set<int>.from(state.skipped);
    if (!next.remove(i)) next.add(i);
    state = state.copyWith(skipped: next);
  }

  /// Marks every gap as skipped (preview only).
  void skipAll() {
    if (state.phase != CheckinPhase.preview) return;
    state = state.copyWith(
      skipped: {for (var i = 0; i < state.gaps.length; i++) i},
    );
  }

  /// Leaves the preview and begins cycling at the first non-skipped gap.
  /// If every gap is skipped (or there are none) → [CheckinPhase.done].
  ///
  /// Any gaps the user toggled off in the preview are dismissed here (so they
  /// don't resurface today) before cycling the rest.
  Future<void> begin() async {
    await _dismissSkipped();
    final start = _firstUnskipped();
    if (start == null) {
      state = state.copyWith(phase: CheckinPhase.done);
      return;
    }
    state = state.copyWith(phase: CheckinPhase.cycling, index: start);
  }

  /// Resolves the current `symptom_gap` with a free-text description and
  /// optional severity, day-anchoring the symptom to the reviewed day.
  Future<void> resolveSymptom({
    required String rawDescription,
    int? severity,
  }) async {
    final gap = state.current;
    if (gap == null) return;
    await _api.resolveSymptomGap(
      mealId: gap.mealId!,
      rawDescription: rawDescription,
      severity: severity,
      loggedAt: _targetDayTimestamp(),
    );
    _advance();
  }

  /// Confirms the current `low_confidence` food guess.
  Future<void> confirmFood() async {
    final gap = state.current;
    if (gap == null) return;
    await _api.resolveFoodGap(
      mealId: gap.mealId!,
      foodName: gap.foodName,
      confirmed: true,
    );
    _advance();
  }

  /// Corrects the current `low_confidence` food guess with new text.
  Future<void> correctFood(String correctedDescription) async {
    final gap = state.current;
    if (gap == null) return;
    await _api.resolveFoodGap(
      mealId: gap.mealId!,
      correctedDescription: correctedDescription,
    );
    _advance();
  }

  /// Logs the meal for the current `missing_chunk` gap.
  Future<void> logMeal(String description) async {
    final gap = state.current;
    if (gap == null) return;
    await _api.resolveMealGap(
      description: description,
      loggedAt: _missingChunkTimestamp(),
    );
    _advance();
  }

  /// Skips the current gap. For a `symptom_gap` this also spends its one evening
  /// retry server-side. Every skipped gap is dismissed so it doesn't resurface
  /// today (a genuinely new gap still appears).
  Future<void> skipCurrent() async {
    final gap = state.current;
    if (gap == null) return;
    if (gap.type == 'symptom_gap') {
      await _api.skipSymptomGap(mealId: gap.mealId!);
    }
    await _dismiss(gap);
    _advance();
  }

  /// Dismisses [gap] for the reviewed day (best-effort — a failed call just
  /// means the gap may resurface). No-op when the gap carries no key.
  Future<void> _dismiss(CheckinGap gap) async {
    final key = gap.gapKey;
    if (key == null) return;
    try {
      await _api.dismissCheckinGap(date: state.targetDate, gapKey: key);
    } catch (_) {
      // Best-effort; swallow so the review flow is never blocked by it.
    }
  }

  /// Dismisses every gap the user toggled off during the preview.
  Future<void> _dismissSkipped() async {
    for (final i in state.skipped) {
      if (i >= 0 && i < state.gaps.length) await _dismiss(state.gaps[i]);
    }
  }

  /// First gap index not in the skip set, or null if none.
  int? _firstUnskipped() {
    for (var i = 0; i < state.gaps.length; i++) {
      if (!state.skipped.contains(i)) return i;
    }
    return null;
  }

  /// Moves to the next gap index strictly after the current one that is not
  /// skipped; if none remain → [CheckinPhase.done].
  void _advance() {
    for (var i = state.index + 1; i < state.gaps.length; i++) {
      if (!state.skipped.contains(i)) {
        state = state.copyWith(index: i);
        return;
      }
    }
    state = state.copyWith(phase: CheckinPhase.done);
  }

  /// A reasonable instant on the reviewed day (local noon) for day-anchored
  /// resolves where the gap carries no window of its own.
  DateTime _targetDayTimestamp() {
    final parts = state.targetDate.split('-');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime(y, m, d, 12);
  }

  /// Timestamp for a logged missing-chunk meal: the gap's own window start when
  /// present, else local noon on the reviewed day.
  DateTime _missingChunkTimestamp() {
    final ws = state.current?.windowStart;
    if (ws != null) return DateTime.parse(ws);
    return _targetDayTimestamp();
  }
}

/// One controller per reviewed day, keyed by the `YYYY-MM-DD` string so the
/// same date always resolves to the same instance (a `DateTime` key would
/// cache per full timestamp). The provider parses the key and injects the
/// shared [HeartyApiClient].
final checkinControllerProvider =
    StateNotifierProvider.family<CheckinController, CheckinState, String>(
  (ref, targetDate) {
    final parts = targetDate.split('-');
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    return CheckinController(ref.read(heartyApiClientProvider), date: date);
  },
);
