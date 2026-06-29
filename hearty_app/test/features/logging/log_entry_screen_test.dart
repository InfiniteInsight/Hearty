import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearty_app/core/api/hearty_api_client.dart';
import 'package:hearty_app/core/api/models/meal_log.dart';
import 'package:hearty_app/core/api/models/symptom_log.dart';
import 'package:hearty_app/core/api/models/user_preferences.dart';
import 'package:hearty_app/core/api/providers/meals_provider.dart';
import 'package:hearty_app/core/api/providers/preferences_provider.dart';
import 'package:hearty_app/core/api/providers/symptoms_provider.dart';
import 'package:hearty_app/features/logging/screens/log_entry_screen.dart';
import 'package:hearty_app/features/voice/models/voice_state.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';

import '../voice/fake_tts_engine.dart';
import '../../core/stt/fake_stt_engine.dart';

/// Records every [logSymptom] call so the feeling follow-up wiring can be
/// asserted. [build] stubs the stream so the DAO is never touched.
class _RecordingSymptomsNotifier extends SymptomsNotifier {
  final List<({String description, int? severity})> calls = [];

  @override
  Stream<List<SymptomLog>> build() => Stream.value(const []);

  @override
  Future<void> logSymptom(String description, {int? severity}) async {
    calls.add((description: description, severity: severity));
  }
}

/// Records [logMeal] calls. When [shouldThrow] is set, [logMeal] throws to
/// simulate a failed log (mirroring the production path which throws on error).
class _RecordingMealsNotifier extends MealsNotifier {
  _RecordingMealsNotifier({this.shouldThrow = false});

  final bool shouldThrow;
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
    if (shouldThrow) {
      throw Exception('log failed');
    }
  }
}

/// A no-op voice notifier so the screen builds without STT/model deps.
class _StubVoiceNotifier extends VoiceNotifier {
  _StubVoiceNotifier()
      : super(
          ttsForTesting: FakeTtsEngine(),
          engineFactory: FakeSttEngine.new,
          releaseWakeWordMic: _noop,
        ) {
    state = const VoiceState(status: VoiceStatus.idle);
  }

  static Future<void> _noop() async {}
}

/// Resolves immediately to default preferences so the screen's
/// `ref.read(preferencesProvider)` doesn't run the real (DAO-backed) build.
class _StubPrefs extends PreferencesNotifier {
  @override
  Future<UserPreferences> build() async => const UserPreferences();
}

/// Classifies every feeling note as a symptom so the Save path logs (the
/// sentiment gate is unit-tested separately in feeling_followup_sheet_test).
class _StubApiClient extends HeartyApiClient {
  _StubApiClient() : super(Dio());
  @override
  Future<bool> classifyFeeling(String text) async => true;
}

Future<({_RecordingSymptomsNotifier symptoms, _RecordingMealsNotifier meals})>
    _pumpLogEntry(
  WidgetTester tester, {
  bool failLog = false,
}) async {
  final symptoms = _RecordingSymptomsNotifier();
  final meals = _RecordingMealsNotifier(shouldThrow: failLog);

  final router = GoRouter(
    initialLocation: '/log',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            const Scaffold(body: Text('HOME', key: Key('stub-home'))),
      ),
      GoRoute(
        path: '/log',
        builder: (context, state) => const Scaffold(
          body: Text('LOG ROOT', key: Key('stub-log-root')),
        ),
        routes: [
          GoRoute(
            path: 'entry',
            builder: (context, state) => const LogEntryScreen(),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        symptomsProvider.overrideWith(() => symptoms),
        mealsProvider.overrideWith(() => meals),
        voiceProvider.overrideWith((_) => _StubVoiceNotifier()),
        preferencesProvider.overrideWith(() => _StubPrefs()),
        heartyApiClientProvider.overrideWithValue(_StubApiClient()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // The screen runs a repeating pulse animation, so pumpAndSettle would never
  // converge. Pump a couple of frames instead.
  await tester.pump();

  // Navigate to the entry screen so context.pop() returns to the log root.
  router.go('/log/entry');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));

  return (symptoms: symptoms, meals: meals);
}

/// Submits text and taps "Log it" to reach the success/failure path. Avoids
/// pumpAndSettle because of the screen's repeating pulse animation; pumps fixed
/// frames long enough for the modal sheet route transition to complete.
Future<void> _logAMeal(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'oatmeal');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();

  await tester.tap(find.text('Log it'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets(
      'successful text log → feeling sheet appears; Save records symptom; pops',
      (tester) async {
    final fakes = await _pumpLogEntry(tester);

    await _logAMeal(tester);

    // The feeling follow-up sheet is showing.
    expect(find.byKey(const Key('feeling-save')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('feeling-note-field')),
      'felt bloated',
    );
    await tester.tap(find.byKey(const Key('feeling-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Symptom recorded (note classified as a symptom by the stub client).
    expect(fakes.symptoms.calls, hasLength(1));
    expect(fakes.symptoms.calls.single.description, 'felt bloated');

    // Sheet closed and the screen popped back to the log root.
    expect(find.byKey(const Key('feeling-save')), findsNothing);
    expect(find.byKey(const Key('stub-log-root')), findsOneWidget);
  });

  testWidgets('failed text log → feeling sheet does NOT appear', (tester) async {
    final fakes = await _pumpLogEntry(tester, failLog: true);

    await _logAMeal(tester);

    expect(fakes.meals.logCalls, 1);
    // No prompt on failure.
    expect(find.byKey(const Key('feeling-save')), findsNothing);
    expect(fakes.symptoms.calls, isEmpty);
    // Still on the entry screen (did not pop).
    expect(find.text('Log it'), findsOneWidget);
  });
}
