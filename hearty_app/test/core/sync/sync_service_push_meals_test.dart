// test/core/sync/sync_service_push_meals_test.dart
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/offline/local_meal_dao.dart';
import 'package:hearty_app/core/offline/offline_database.dart';
import 'package:hearty_app/core/sync/sync_service.dart';

/// Captures the outgoing request and short-circuits it with a canned response,
/// so no real HTTP is performed. Mirrors the DI style used elsewhere in the
/// repo (see hearty_api_client_meals_test.dart).
class _CapturingInterceptor extends Interceptor {
  RequestOptions? lastRequest;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastRequest = options;
    handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'id': 'srv-1'},
      ),
    );
  }
}

void main() {
  late OfflineDatabase db;
  late LocalMealDao dao;
  late Dio dio;
  late _CapturingInterceptor interceptor;
  late ProviderContainer container;
  late SyncService service;

  setUp(() {
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
    dao = LocalMealDao(db);
    dio = Dio();
    interceptor = _CapturingInterceptor();
    dio.interceptors.add(interceptor);
    container = ProviderContainer();
    final ref = container.read(Provider<Ref>((ref) => ref));
    service = SyncService(db, dio, ref);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('includes foods in POST body when local foods is non-empty', () async {
    await dao.insertLocal(
      localId: 'm1',
      description: 'salmon and veg',
      mealType: 'dinner',
      foods: ['grilled salmon', 'broccoli'],
      loggedAt: DateTime.now(),
    );

    await service.pushMeals();

    final req = interceptor.lastRequest!;
    expect(req.path, '/api/meals');
    expect(req.method, 'POST');
    final body = req.data as Map<String, dynamic>;
    expect(body['description'], 'salmon and veg');
    expect(body['meal_type'], 'dinner');
    expect(body['foods'], ['grilled salmon', 'broccoli']);
  });

  test('omits foods key when local foods is empty (voice/text path)', () async {
    await dao.insertLocal(
      localId: 'm2',
      description: 'I had a sandwich',
      mealType: 'lunch',
      foods: [],
      loggedAt: DateTime.now(),
    );

    await service.pushMeals();

    final req = interceptor.lastRequest!;
    expect(req.path, '/api/meals');
    expect(req.method, 'POST');
    final body = req.data as Map<String, dynamic>;
    expect(body['description'], 'I had a sandwich');
    expect(body['meal_type'], 'lunch');
    expect(body.containsKey('foods'), isFalse);
  });
}
