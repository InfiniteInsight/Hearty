// test/core/offline/local_voice_queue_dao_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/offline/offline_database.dart';
import 'package:hearty_app/core/offline/local_voice_queue_dao.dart';

OfflineDatabase _makeDb() => OfflineDatabase.forTesting(NativeDatabase.memory());

void main() {
  late OfflineDatabase db;
  late LocalVoiceQueueDao dao;

  setUp(() {
    db = _makeDb();
    dao = LocalVoiceQueueDao(db);
  });

  tearDown(() => db.close());

  test('insertPending and getPending return the entry', () async {
    await dao.insertPending(id: 'vq-1', transcript: 'I had oatmeal for breakfast', loggedAt: DateTime.now());
    final pending = await dao.getPending();
    expect(pending.length, 1);
    expect(pending.first.transcript, 'I had oatmeal for breakfast');
    expect(pending.first.syncStatus, 'pending');
  });

  test('markDone removes entry from pending', () async {
    await dao.insertPending(id: 'vq-2', transcript: 'Lunch salad', loggedAt: DateTime.now());
    await dao.markDone('vq-2');
    final pending = await dao.getPending();
    expect(pending.isEmpty, true);
  });

  test('markFailed sets syncStatus to failed', () async {
    await dao.insertPending(id: 'vq-3', transcript: 'Dinner', loggedAt: DateTime.now());
    await dao.markFailed('vq-3');
    final row = await (db.select(db.localVoiceQueue)
          ..where((v) => v.id.equals('vq-3')))
        .getSingle();
    expect(row.syncStatus, 'failed');
  });

  test('watchPending emits pending entries and updates when one is removed', () async {
    await dao.insertPending(
      id: 'vq-watch-1',
      transcript: 'I had oatmeal',
      loggedAt: DateTime.now(),
    );
    await dao.insertPending(
      id: 'vq-watch-2',
      transcript: 'And a coffee',
      loggedAt: DateTime.now(),
    );

    // First emission: both entries present.
    final first = await dao.watchPending().first;
    expect(first.length, 2);

    // After markDone, stream should emit with one entry removed.
    await dao.markDone('vq-watch-1');
    final second = await dao.watchPending().first;
    expect(second.length, 1);
    expect(second.first.id, 'vq-watch-2');
  });
}
