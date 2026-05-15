// test/core/offline/local_wellbeing_dao_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/wellbeing_log.dart';
import 'package:hearty_app/core/offline/offline_database.dart';
import 'package:hearty_app/core/offline/local_wellbeing_dao.dart';

OfflineDatabase _makeDb() => OfflineDatabase.forTesting(NativeDatabase.memory());

void main() {
  late OfflineDatabase db;
  late LocalWellbeingDao dao;

  setUp(() {
    db = _makeDb();
    dao = LocalWellbeingDao(db);
  });

  tearDown(() => db.close());

  test('insertLocal and watchToday emit the entry', () async {
    await dao.insertLocal(
      localId: 'wb-1',
      energy: 4,
      mood: 3,
      notes: 'Feeling okay',
      period: 'morning',
      loggedAt: DateTime.now(),
    );
    final entries = await dao.watchToday().first;
    expect(entries.length, 1);
    expect(entries.first.energy, 4);
    expect(entries.first.notes, 'Feeling okay');
  });

  test('updateLocal writes updated fields as pending', () async {
    await dao.insertLocal(
      localId: 'wb-2',
      energy: 2,
      mood: 2,
      loggedAt: DateTime.now(),
    );
    await dao.markSynced('wb-2', 'srv-wb-2');

    await dao.updateLocal('wb-2', energy: 5, mood: 5, notes: 'Much better');

    final row = await (db.select(db.localWellbeing)
          ..where((w) => w.id.equals('wb-2')))
        .getSingle();
    expect(row.energy, 5);
    expect(row.syncStatus, 'pending');
    expect(row.serverId, 'srv-wb-2'); // serverId preserved
  });

  test('getPending returns only pending rows', () async {
    await dao.insertLocal(
      localId: 'wb-3',
      energy: 3,
      mood: 3,
      loggedAt: DateTime.now(),
    );
    await dao.markSynced('wb-3', 'srv-wb-3');
    await dao.insertLocal(
      localId: 'wb-4',
      energy: 4,
      mood: 4,
      loggedAt: DateTime.now(),
    );

    final pending = await dao.getPending();
    expect(pending.length, 1);
    expect(pending.first.id, 'wb-4');
  });
}
