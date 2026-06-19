import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/trends_turn.dart';
import 'package:hearty_app/features/trends/providers/trends_conversation_provider.dart';

/// Records the two trends methods the controller uses and returns a scripted
/// queue of [TrendsTurn]s. Implements [HeartyApiClient] but only overrides what
/// the controller touches; [noSuchMethod] makes any other call fail loudly.
class FakeHeartyApiClient implements HeartyApiClient {
  FakeHeartyApiClient({List<TrendsTurn>? turns, this.throwOnTurn = false})
      : _turns = turns ?? const [];

  final List<TrendsTurn> _turns;
  bool throwOnTurn;
  int _turnIndex = 0;

  // Recorded calls.
  final List<List<Map<String, String>>> turnHistories = [];
  final List<Map<String, dynamic>> verdictCalls = [];

  @override
  Future<TrendsTurn> trendsConversation(List<Map<String, String>> history) async {
    // Snapshot the history so later mutation can't retroactively change it.
    turnHistories.add(history.map((m) => Map<String, String>.from(m)).toList());
    if (throwOnTurn) throw Exception('boom');
    final turn = _turns[_turnIndex];
    if (_turnIndex < _turns.length - 1) _turnIndex++;
    return turn;
  }

  @override
  Future<void> submitSignalVerdict({
    required String category,
    required String outcomeType,
    required String outcomeName,
    required String verdict,
  }) async {
    verdictCalls.add({
      'category': category,
      'outcomeType': outcomeType,
      'outcomeName': outcomeName,
      'verdict': verdict,
    });
  }

  // Any other client method being hit is a test failure, not a silent no-op.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TrendsTurn _turn(
  String reply, {
  ProposedVerdict? verdict,
  bool isClosing = false,
}) =>
    TrendsTurn(reply: reply, proposedVerdict: verdict, isClosing: isClosing);

const _verdict = ProposedVerdict(
  category: 'dairy',
  categoryLabel: 'Dairy / Casein',
  outcomeType: 'symptom',
  outcomeName: 'bloating',
  verdict: 'confirmed',
);

void main() {
  group('start()', () {
    test('populates currentReply, history, and pendingVerdict', () async {
      final api = FakeHeartyApiClient(
        turns: [_turn('Looking at last month…', verdict: _verdict)],
      );
      final c = TrendsConversationController(api);

      await c.start();

      expect(c.state.phase, TrendsConvoPhase.active);
      expect(c.state.currentReply, 'Looking at last month…');
      expect(c.state.history, [
        {'role': 'assistant', 'content': 'Looking at last month…'},
      ]);
      expect(c.state.pendingVerdict, isNotNull);
      expect(c.state.pendingVerdict!.outcomeName, 'bloating');
      // First turn is fetched with an empty history.
      expect(api.turnHistories.single, isEmpty);
    });

    test('isClosing sets the flag but stays active', () async {
      final api = FakeHeartyApiClient(turns: [_turn('All caught up.', isClosing: true)]);
      final c = TrendsConversationController(api);

      await c.start();

      expect(c.state.phase, TrendsConvoPhase.active);
      expect(c.state.isClosing, isTrue);
    });

    test('throw → error phase', () async {
      final api = FakeHeartyApiClient(throwOnTurn: true, turns: [_turn('x')]);
      final c = TrendsConversationController(api);

      await c.start();

      expect(c.state.phase, TrendsConvoPhase.error);
    });
  });

  group('sendUserTurn', () {
    test('appends the user turn to the sent history and fetches the next turn',
        () async {
      final api = FakeHeartyApiClient(turns: [
        _turn('Hi there, ready to review?'),
        _turn('Got it, thanks.'),
      ]);
      final c = TrendsConversationController(api);
      await c.start();

      await c.sendUserTurn('Sounds good');

      // The history sent on the second turn includes the new user message.
      expect(api.turnHistories.last, [
        {'role': 'assistant', 'content': 'Hi there, ready to review?'},
        {'role': 'user', 'content': 'Sounds good'},
      ]);
      // The assistant reply is appended and surfaced.
      expect(c.state.currentReply, 'Got it, thanks.');
      expect(c.state.history.last, {
        'role': 'assistant',
        'content': 'Got it, thanks.',
      });
      expect(c.state.busy, isFalse);
    });

    test('blank input is ignored (no API call)', () async {
      final api = FakeHeartyApiClient(turns: [_turn('Hi')]);
      final c = TrendsConversationController(api);
      await c.start();

      await c.sendUserTurn('   ');

      expect(api.turnHistories, hasLength(1)); // only the start() call
    });

    test('throw → error phase', () async {
      final api = FakeHeartyApiClient(turns: [_turn('Hi')]);
      final c = TrendsConversationController(api);
      await c.start();
      api.throwOnTurn = true;

      await c.sendUserTurn('hello');

      expect(c.state.phase, TrendsConvoPhase.error);
    });
  });

  group('verdicts', () {
    test('confirmVerdict submits exactly once with the pending fields, '
        'then clears it', () async {
      final api = FakeHeartyApiClient(
        turns: [_turn('Reviewing…', verdict: _verdict)],
      );
      final c = TrendsConversationController(api);
      await c.start();

      await c.confirmVerdict();

      expect(api.verdictCalls, hasLength(1));
      expect(api.verdictCalls.single, {
        'category': 'dairy',
        'outcomeType': 'symptom',
        'outcomeName': 'bloating',
        'verdict': 'confirmed',
      });
      expect(c.state.pendingVerdict, isNull);
    });

    test('dismissVerdict clears WITHOUT calling the API', () async {
      final api = FakeHeartyApiClient(
        turns: [_turn('Reviewing…', verdict: _verdict)],
      );
      final c = TrendsConversationController(api);
      await c.start();

      c.dismissVerdict();

      expect(api.verdictCalls, isEmpty);
      expect(c.state.pendingVerdict, isNull);
    });

    test('confirmVerdict is a no-op when nothing is pending', () async {
      final api = FakeHeartyApiClient(turns: [_turn('No signal here.')]);
      final c = TrendsConversationController(api);
      await c.start();

      await c.confirmVerdict();

      expect(api.verdictCalls, isEmpty);
    });
  });

  test('close() moves to closed', () async {
    final api = FakeHeartyApiClient(turns: [_turn('Hi')]);
    final c = TrendsConversationController(api);
    await c.start();

    c.close();

    expect(c.state.phase, TrendsConvoPhase.closed);
  });
}
