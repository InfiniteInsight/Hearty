// test/core/offline/local_symptom_dao_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/symptom_log.dart';
import 'package:hearty_app/core/offline/offline_database.dart';
import 'package:hearty_app/core/offline/local_symptom_dao.dart';

OfflineDatabase _makeDb() => OfflineDatabase.forTesting(NativeDatabase.memory());

void main() {
  late OfflineDatabase db;
  late LocalSymptomDao dao;

  setUp(() {
    db = _makeDb();
    dao = LocalSymptomDao(db);
  });

  tearDown(() => db.close());

  test('insertLocal and watchToday emit the symptom', () async {
    await dao.insertLocal(
      localId: 'sym-1',
      description: 'Bloating',
      severity: 3,
      loggedAt: DateTime.now(),
    );
    final symptoms = await dao.watchToday().first;
    expect(symptoms.length, 1);
    expect(symptoms.first.description, 'Bloating');
    expect(symptoms.first.severity, 3);
  });

  test('getPending returns only pending rows', () async {
    await dao.insertLocal(
      localId: 'sym-2',
      description: 'Nausea',
      severity: 2,
      loggedAt: DateTime.now(),
    );
    await dao.markSynced('sym-2', 'srv-sym-2');
    await dao.insertLocal(
      localId: 'sym-3',
      description: 'Cramps',
      severity: 4,
      loggedAt: DateTime.now(),
    );

    final pending = await dao.getPending();
    expect(pending.length, 1);
    expect(pending.first.id, 'sym-3');
  });

  test('upsertFromServer skips pending records', () async {
    await dao.insertLocal(
      localId: 'sym-4',
      description: 'Local',
      severity: 1,
      loggedAt: DateTime.now(),
    );
    await dao.markSynced('sym-4', 'srv-4');
    await (db.update(db.localSymptoms)..where((s) => s.id.equals('sym-4')))
        .write(const LocalSymptomsCompanion(syncStatus: Value('pending')));

    await dao.upsertFromServer(SymptomLog(
      id: 'srv-4',
      description: 'Server version',
      severity: 5,
      loggedAt: DateTime.now(),
    ));

    final row = await (db.select(db.localSymptoms)
          ..where((s) => s.id.equals('sym-4')))
        .getSingle();
    expect(row.description, 'Local');
  });
}
