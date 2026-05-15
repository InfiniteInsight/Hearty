// test/core/offline/local_preferences_dao_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/user_preferences.dart';
import 'package:hearty_app/core/offline/offline_database.dart';
import 'package:hearty_app/core/offline/local_preferences_dao.dart';

OfflineDatabase _makeDb() => OfflineDatabase.forTesting(NativeDatabase.memory());

void main() {
  late OfflineDatabase db;
  late LocalPreferencesDao dao;

  setUp(() {
    db = _makeDb();
    dao = LocalPreferencesDao(db);
  });

  tearDown(() => db.close());

  test('read returns null when empty', () async {
    expect(await dao.read(), isNull);
  });

  test('write and read roundtrip UserPreferences', () async {
    const prefs = UserPreferences(allergens: ['Gluten', 'Dairy']);
    await dao.write(prefs, syncStatus: 'pending');
    final result = await dao.read();
    expect(result, isNotNull);
    expect(result!.allergens, ['Gluten', 'Dairy']);
  });

  test('markSynced sets syncStatus to synced', () async {
    await dao.write(const UserPreferences(), syncStatus: 'pending');
    await dao.markSynced();
    final row = await (db.select(db.localPreferences)).getSingle();
    expect(row.syncStatus, 'synced');
  });

  test('isPending returns true when syncStatus is pending', () async {
    await dao.write(const UserPreferences(), syncStatus: 'pending');
    expect(await dao.isPending(), isTrue);
    await dao.markSynced();
    expect(await dao.isPending(), isFalse);
  });
}
