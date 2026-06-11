import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/voice/models/voice_state.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';
import 'package:hearty_app/features/voice/screens/voice_overlay_screen.dart';
import 'package:hearty_app/features/voice/widgets/prism_waveform.dart';
import 'fake_tts_engine.dart';
import '../../core/stt/fake_stt_engine.dart';

void main() {
  group('VoiceOverlayScreen', () {
    testWidgets('listening before the mic is live shows "getting ready", not '
        'a flat waveform (#18)', (tester) async {
      // status=listening with the default (pre-capture) micPhase means the mic
      // isn't live yet — e.g. a cold on-device model is warming. The overlay
      // must show the getting-ready indicator, not a dead flat prism. The live
      // waveform is covered by 'listening phase shows waveform' below.
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
      expect(find.byKey(const Key('getting_ready_hint')), findsOneWidget);
      expect(find.byType(PrismWaveform), findsNothing);
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
      expect(find.byType(PrismWaveform), findsNothing);
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

    testWidgets('preparing phase shows Getting ready hint, no waveform', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.awaitingFollowUp,
                response: 'How are you feeling?',
                micPhase: MicPhase.preparing,
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('getting_ready_hint')), findsOneWidget);
      expect(find.byType(PrismWaveform), findsNothing);
    });

    testWidgets('paused phase shows Tap to talk button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.awaitingFollowUp,
                response: 'How are you feeling?',
                micPhase: MicPhase.paused,
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('tap_to_talk_button')), findsOneWidget);
      expect(find.byType(PrismWaveform), findsNothing);
    });

    testWidgets('listening phase shows waveform', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.awaitingFollowUp,
                response: 'How are you feeling?',
                micPhase: MicPhase.listening,
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byType(PrismWaveform), findsOneWidget);
      expect(find.byKey(const Key('getting_ready_hint')), findsNothing);
      expect(find.byKey(const Key('tap_to_talk_button')), findsNothing);
    });
  });
}

class _StubVoiceNotifier extends VoiceNotifier {
  _StubVoiceNotifier(VoiceState initial)
      : super(
          ttsForTesting: FakeTtsEngine(),
          engineFactory: FakeSttEngine.new,
          releaseWakeWordMic: _noop,
        ) {
    state = initial;
  }

  static Future<void> _noop() async {}
}
