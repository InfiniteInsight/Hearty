import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:hearty_app/features/voice/models/voice_state.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';
import 'package:hearty_app/features/voice/screens/voice_overlay_screen.dart';
import 'fake_tts_engine.dart';

void main() {
  group('VoiceOverlayScreen', () {
    testWidgets('shows waveform when status is listening', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(status: VoiceStatus.listening)),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('waveform_animation')), findsOneWidget);
      expect(find.byKey(const Key('thinking_animation')), findsNothing);
    });

    testWidgets('shows thinking animation when status is thinking', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(status: VoiceStatus.thinking)),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('thinking_animation')), findsOneWidget);
      expect(find.byKey(const Key('waveform_animation')), findsNothing);
    });

    testWidgets('shows transcript text when available', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.listening,
                transcript: 'I had pizza',
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.text('I had pizza'), findsOneWidget);
    });

    testWidgets('shows response text when responding', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.responding,
                response: 'Logged your meal!',
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.text('Logged your meal!'), findsOneWidget);
    });

    testWidgets('shows text field for manual input', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(status: VoiceStatus.listening)),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}

class _FakeStt extends Fake implements SpeechToText {
  @override
  bool get isListening => false;
  @override
  bool get isNotListening => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value();
}

class _StubVoiceNotifier extends VoiceNotifier {
  _StubVoiceNotifier(VoiceState initial)
      : super(sttForTesting: _FakeStt(), ttsForTesting: FakeTtsEngine()) {
    state = initial;
  }
}
