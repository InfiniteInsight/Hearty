import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/meal_log.dart';
import 'package:hearty_app/core/api/models/photo_analysis.dart';
import 'package:hearty_app/core/api/models/symptom_log.dart';
import 'package:hearty_app/core/api/providers/meals_provider.dart';
import 'package:hearty_app/core/api/providers/symptoms_provider.dart';
import 'package:hearty_app/features/logging/widgets/editable_food_list.dart';
import 'package:hearty_app/features/photos/models/photo_type.dart';
import 'package:hearty_app/features/photos/models/photo_upload_response.dart';
import 'package:hearty_app/features/photos/providers/photo_provider.dart';
import 'package:hearty_app/features/photos/screens/photo_review_screen.dart';
import 'package:hearty_app/features/photos/screens/photo_upload_flow_screen.dart';

/// Fake client driving the photo flow through an overridden
/// [heartyApiClientProvider] (mirrors the trends widget-test harness).
class FakeHeartyApiClient implements HeartyApiClient {
  FakeHeartyApiClient(this._status);

  final PhotoAnalysis _status;
  int retryCalls = 0;

  @override
  Future<String> uploadFoodPhoto({
    required List<int> bytes,
    required String filename,
    String type = 'food_plate',
    String? mealId,
  }) async =>
      'photo-1';

  @override
  Future<PhotoUploadResponse> uploadPhoto({
    required File file,
    required String photoType,
  }) async =>
      const PhotoUploadResponse(
        id: 'photo-1',
        type: 'barcode',
        status: 'processing',
        message: '',
      );

  @override
  Future<PhotoAnalysis> fetchPhotoStatus(String photoId) async => _status;

  @override
  Future<void> retryPhoto(String photoId) async {
    retryCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [PhotoNotifier] pre-seeded into a fixed state. [uploadAndPoll] is a no-op
/// so the flow screen's didChangeDependencies doesn't overwrite the seed; only
/// [retry] is observed.
class _FakePhotoNotifier extends PhotoNotifier {
  _FakePhotoNotifier(PhotoState seed) : super(FakeHeartyApiClient(_dummy)) {
    state = seed;
  }

  static const _dummy = PhotoAnalysis(id: '', type: 'food_plate', status: '');

  int retryCalls = 0;

  @override
  Future<void> uploadAndPoll(File file, PhotoType type) async {}

  @override
  void reset() {}

  @override
  Future<void> retry() async {
    retryCalls++;
  }
}

/// Records [logMeal] calls so the save path (screen -> mealsProvider -> DAO)
/// can be asserted without a real database. [build] emits an empty stream so
/// the screen renders normally.
class _RecordingMealsNotifier extends MealsNotifier {
  _RecordingMealsNotifier({this.shouldThrow = false});

  final bool shouldThrow;
  String? loggedDescription;
  List<String>? loggedFoods;
  String? loggedInputMethod;
  int logCalls = 0;

  @override
  Stream<List<MealLog>> build() => Stream.value(const <MealLog>[]);

  @override
  Future<void> logMeal(
    String description, {
    String? mealType,
    List<String>? foods,
    String inputMethod = 'voice',
  }) async {
    logCalls++;
    loggedDescription = description;
    loggedFoods = foods;
    loggedInputMethod = inputMethod;
    if (shouldThrow) {
      throw Exception('log failed');
    }
  }
}

/// Records [logSymptom] calls so the feeling follow-up wiring can be asserted.
class _RecordingSymptomsNotifier extends SymptomsNotifier {
  final List<({String description, int? severity})> calls = [];

  @override
  Stream<List<SymptomLog>> build() => Stream.value(const []);

  @override
  Future<void> logSymptom(String description, {int? severity}) async {
    calls.add((description: description, severity: severity));
  }
}

/// Pumps [PhotoReviewScreen] inside a GoRouter so `context.go('/home')`
/// resolves, with the meals + symptoms providers overridden.
Future<({_RecordingMealsNotifier meals, _RecordingSymptomsNotifier symptoms})>
    _pumpReview(
  WidgetTester tester, {
  required PhotoAnalysis analysis,
  bool failLog = false,
}) async {
  final meals = _RecordingMealsNotifier(shouldThrow: failLog);
  final symptoms = _RecordingSymptomsNotifier();

  final router = GoRouter(
    initialLocation: '/review',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            const Scaffold(body: Text('HOME', key: Key('stub-home'))),
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) => PhotoReviewScreen(
          analysis: analysis,
          photoType: PhotoType.foodPlate,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mealsProvider.overrideWith(() => meals),
        symptomsProvider.overrideWith(() => symptoms),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (meals: meals, symptoms: symptoms);
}

void main() {
  group('PhotoReviewScreen (complete)', () {
    testWidgets('renders detected foods as an editable list', (tester) async {
      const analysis = PhotoAnalysis(
        id: 'photo-1',
        type: 'food_plate',
        status: 'complete',
        foods: [
          IdentifiedFood(
            name: 'Grilled salmon',
            portion: 'approximately 1 fillet',
            confidence: 0.82,
          ),
          IdentifiedFood(name: 'Side salad', confidence: 0.4),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: PhotoReviewScreen(
              analysis: analysis,
              photoType: PhotoType.foodPlate,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Detected Foods'), findsOneWidget);
      // The detected foods are now editable, not read-only Text.
      expect(find.byType(EditableFoodList), findsOneWidget);
      final foodFields = find.descendant(
        of: find.byType(EditableFoodList),
        matching: find.byType(TextField),
      );
      expect(foodFields, findsNWidgets(2));

      // Names are pre-filled into the editable rows.
      expect(
        tester.widget<TextField>(foodFields.at(0)).controller!.text,
        'Grilled salmon',
      );
      expect(
        tester.widget<TextField>(foodFields.at(1)).controller!.text,
        'Side salad',
      );
    });

    testWidgets(
        'editing, removing and adding foods then saving logs the corrected '
        'list verbatim with inputMethod photo', (tester) async {
      const analysis = PhotoAnalysis(
        id: 'photo-1',
        type: 'food_plate',
        status: 'complete',
        foods: [
          IdentifiedFood(name: 'Grilled salmon', confidence: 0.82),
          IdentifiedFood(name: 'Side salad', confidence: 0.4),
        ],
      );

      final notifier = _RecordingMealsNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mealsProvider.overrideWith(() => notifier)],
          child: MaterialApp(
            home: PhotoReviewScreen(
              analysis: analysis,
              photoType: PhotoType.foodPlate,
            ),
          ),
        ),
      );
      await tester.pump();

      Finder foodFields() => find.descendant(
            of: find.byType(EditableFoodList),
            matching: find.byType(TextField),
          );

      // Edit the first food name.
      await tester.enterText(foodFields().at(0), 'Baked salmon');
      await tester.pump();

      // Remove the second food ('Side salad').
      await tester.tap(find.widgetWithIcon(IconButton, Icons.close).at(1));
      await tester.pump();

      // Add a new food.
      await tester.tap(find.text('Add food'));
      await tester.pump();
      await tester.enterText(foodFields().last, 'Steamed broccoli');
      await tester.pump();

      // Save.
      await tester.tap(find.text('Looks good — Save'));
      // The save spinner keeps animating while the sheet is open, so
      // pumpAndSettle cannot converge; pump fixed frames for the sheet route.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Saving now opens the feeling follow-up sheet before navigating; dismiss
      // it so the route animation/timers settle.
      expect(find.byKey(const Key('feeling-skip')), findsOneWidget);
      await tester.tap(find.byKey(const Key('feeling-skip')));
      await tester.pumpAndSettle();

      expect(notifier.logCalls, 1);
      expect(notifier.loggedInputMethod, 'photo');
      // The corrected names are sent verbatim — NOT the raw vision names.
      expect(notifier.loggedFoods, ['Baked salmon', 'Steamed broccoli']);
      expect(notifier.loggedFoods, isNot(contains('Grilled salmon')));
      expect(notifier.loggedFoods, isNot(contains('Side salad')));
    });

    testWidgets(
        'successful save → feeling sheet appears; Skip records nothing and goes '
        'to /home', (tester) async {
      const analysis = PhotoAnalysis(
        id: 'photo-1',
        type: 'food_plate',
        status: 'complete',
        foods: [IdentifiedFood(name: 'Apple', confidence: 0.9)],
      );

      final fakes = await _pumpReview(tester, analysis: analysis);

      await tester.tap(find.text('Looks good — Save'));
      // The save spinner keeps animating while the sheet is open, so
      // pumpAndSettle cannot converge; pump fixed frames for the sheet route.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Feeling sheet showing.
      expect(find.byKey(const Key('feeling-skip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('feeling-skip')));
      await tester.pumpAndSettle();

      // Skip records nothing.
      expect(fakes.symptoms.calls, isEmpty);
      // Proceeded to /home.
      expect(find.byKey(const Key('stub-home')), findsOneWidget);
    });

    testWidgets('failed save → feeling sheet does NOT appear (snackbar shown)',
        (tester) async {
      const analysis = PhotoAnalysis(
        id: 'photo-1',
        type: 'food_plate',
        status: 'complete',
        foods: [IdentifiedFood(name: 'Apple', confidence: 0.9)],
      );

      final fakes =
          await _pumpReview(tester, analysis: analysis, failLog: true);

      await tester.tap(find.text('Looks good — Save'));
      await tester.pumpAndSettle();

      expect(fakes.meals.logCalls, 1);
      // No prompt on failure.
      expect(find.byKey(const Key('feeling-skip')), findsNothing);
      expect(fakes.symptoms.calls, isEmpty);
      // Did not navigate; failure snackbar shown instead.
      expect(find.byKey(const Key('stub-home')), findsNothing);
      expect(find.text('Failed to save — please try again.'), findsOneWidget);
    });
  });

  group('PhotoUploadFlowScreen (failed)', () {
    testWidgets('shows the backend error plus retry + manual fallback',
        (tester) async {
      // Override photoProvider with a notifier seeded straight into the failed
      // state, so the flow screen's failure-branch rendering is what's tested
      // (the real upload/poll timing + file IO is device-verified separately).
      final notifier = _FakePhotoNotifier(
        const PhotoState(
          photoId: 'photo-1',
          analysis: PhotoAnalysis(
            id: 'photo-1',
            type: 'food_plate',
            status: 'failed',
            error: 'Vision model unavailable',
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [photoProvider.overrideWith((ref) => notifier)],
          child: MaterialApp(
            home: PhotoUploadFlowScreen(
              file: File('ignored-by-fake-notifier.jpg'),
              photoType: PhotoType.foodPlate,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Vision model unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Enter manually'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(notifier.retryCalls, 1);
    });

    testWidgets('starts the upload from a post-frame callback, not during build',
        (tester) async {
      // The flow screen must kick off the upload AFTER the first frame, never
      // by mutating photoProvider inside didChangeDependencies. Mutating during
      // build throws "modify a provider while the widget tree was building" on
      // device (left the screen stuck on "Analyzing food"); that assertion is a
      // runtime-only check, so this test guards the corrected behaviour — the
      // real upload still fires post-frame — while the crash itself is
      // device-verified. Drives the REAL notifier so the deferral is exercised.
      final api = FakeHeartyApiClient(const PhotoAnalysis(
        id: 'photo-1',
        type: 'barcode',
        status: 'complete',
        foods: [IdentifiedFood(name: 'apple')],
      ));
      // Owned + disposed by the ProviderScope below (no manual addTearDown).
      final notifier =
          PhotoNotifier(api, pollInterval: const Duration(milliseconds: 1));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [photoProvider.overrideWith((ref) => notifier)],
          child: MaterialApp(
            home: PhotoUploadFlowScreen(
              file: File('unused-barcode-path.jpg'),
              photoType: PhotoType.barcode,
            ),
          ),
        ),
      );
      // First frame: the post-frame callback runs and starts the upload.
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Drain the upload future + the 1ms poll so the flow reaches a result.
      await tester.pump(const Duration(milliseconds: 5));
      expect(notifier.state.analysis?.isComplete ?? false, isTrue);
    });
  });

  group('PhotoNotifier poll termination', () {
    // Drives the REAL uploadAndPoll -> _poll loop (the load-bearing fix:
    // terminate on backend status 'failed', formerly the stale 'error').
    // Uses PhotoType.barcode so the File-based uploadPhoto path runs (no
    // readAsBytes file IO) and a ~zero poll interval so no real wait is needed.
    test('stores analysis and stops polling when status is failed', () async {
      final api = FakeHeartyApiClient(const PhotoAnalysis(
        id: 'photo-1',
        type: 'barcode',
        status: 'failed',
        error: 'boom',
      ));
      final notifier =
          PhotoNotifier(api, pollInterval: const Duration(milliseconds: 1));
      addTearDown(notifier.dispose);

      await notifier.uploadAndPoll(
        File('unused-barcode-path.jpg'),
        PhotoType.barcode,
      );

      expect(notifier.state.isPolling, isFalse);
      expect(notifier.state.analysis, isNotNull);
      expect(notifier.state.analysis!.isFailed, isTrue);
      expect(notifier.state.analysis!.error, 'boom');
      // The generic timeout error must NOT be set — the loop terminated on the
      // 'failed' status, not by running out of attempts.
      expect(notifier.state.error, isNull);
    });

    test('stores analysis when status is complete', () async {
      final api = FakeHeartyApiClient(const PhotoAnalysis(
        id: 'photo-1',
        type: 'barcode',
        status: 'complete',
        foods: [IdentifiedFood(name: 'apple')],
      ));
      final notifier =
          PhotoNotifier(api, pollInterval: const Duration(milliseconds: 1));
      addTearDown(notifier.dispose);

      await notifier.uploadAndPoll(
        File('unused-barcode-path.jpg'),
        PhotoType.barcode,
      );

      expect(notifier.state.isPolling, isFalse);
      expect(notifier.state.analysis!.isComplete, isTrue);
      expect(notifier.state.error, isNull);
    });
  });
}
