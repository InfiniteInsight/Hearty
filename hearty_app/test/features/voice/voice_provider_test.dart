import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hearty_app/features/voice/models/voice_state.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';
import 'package:hearty_app/core/audio/audio_beep_channel.dart';
import 'package:hearty_app/core/stt/stt_engine.dart';
import 'package:hearty_app/core/stt/asr_model_manager.dart';
import 'fake_tts_engine.dart';
import '../../core/stt/fake_stt_engine.dart';

class FakeBeepChannel implements AudioBeepChannel {
  int suppressCount = 0;
  int restoreCount = 0;
  int dingCount = 0;
  @override
  Future<void> suppress() async => suppressCount++;
  @override
  Future<void> restore() async => restoreCount++;
  @override
  Future<void> ding() async => dingCount++;
}

/// Hands out a fresh [FakeSttEngine] per capture session (the notifier opens a
/// new engine each session) while tracking the latest one and the total count.
class EngineHarness {
  FakeSttEngine? latest;
  int creations = 0;
  bool nextThrowOnStart = false;
  SttEngine create() {
    final e = FakeSttEngine()..throwOnStart = nextThrowOnStart;
    latest = e;
    creations++;
    return e;
  }
}

/// Drains queued microtasks/zero-timers so the async [_openSession] chain
/// (close → mic handoff → engine.start) settles.
Future<void> pump([int times = 6]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('VoiceNotifier state transitions', () {
    late EngineHarness h;
    late FakeTtsEngine tts;
    late FakeBeepChannel beep;
    late ProviderContainer container;

    setUp(() {
      h = EngineHarness();
      tts = FakeTtsEngine(fireCompletionOnSpeak: false);
      beep = FakeBeepChannel();
      container = ProviderContainer(
        overrides: [
          voiceProvider.overrideWith(
            (ref) => VoiceNotifier(
              ref: ref,
              ttsForTesting: tts,
              engineFactory: h.create,
              beepChannelForTesting: beep,
              releaseWakeWordMic: () async {},
              micHandoffDelay: Duration.zero,
              followUpStartDelay: Duration.zero,
            ),
          ),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is idle', () {
      expect(container.read(voiceProvider).status, VoiceStatus.idle);
    });

    test('startListening transitions to listening', () {
      container.read(voiceProvider.notifier).startListening();
      expect(container.read(voiceProvider).status, VoiceStatus.listening);
    });

    test('setTranscript updates transcript text', () {
      container.read(voiceProvider.notifier).startListening();
      container.read(voiceProvider.notifier).setTranscript('I just had pizza');
      expect(container.read(voiceProvider).transcript, 'I just had pizza');
    });

    test('setThinking transitions to thinking', () {
      container.read(voiceProvider.notifier).startListening();
      container.read(voiceProvider.notifier).setThinking();
      expect(container.read(voiceProvider).status, VoiceStatus.thinking);
    });

    test('setResponse transitions to responding with response text', () {
      container.read(voiceProvider.notifier).setThinking();
      container
          .read(voiceProvider.notifier)
          .setResponse('Logged! How are you feeling?');
      expect(container.read(voiceProvider).status, VoiceStatus.responding);
      expect(
        container.read(voiceProvider).response,
        'Logged! How are you feeling?',
      );
    });

    test('dismiss resets to idle', () {
      container.read(voiceProvider.notifier).setResponse('Done');
      container.read(voiceProvider.notifier).dismiss();
      expect(container.read(voiceProvider).status, VoiceStatus.idle);
    });

    test('stopSpeaking resets to idle from responding state', () {
      container.read(voiceProvider.notifier).setResponse('Good job!');
      container.read(voiceProvider.notifier).stopSpeaking();
      expect(container.read(voiceProvider).status, VoiceStatus.idle);
    });

    test('initial state has MicPhase.none', () {
      expect(container.read(voiceProvider).micPhase, MicPhase.none);
    });

    test('copyWith updates micPhase', () {
      const s = VoiceState();
      expect(
        s.copyWith(micPhase: MicPhase.listening).micPhase,
        MicPhase.listening,
      );
      // unspecified copyWith preserves existing value
      expect(
        s
            .copyWith(micPhase: MicPhase.paused)
            .copyWith(transcript: 'x')
            .micPhase,
        MicPhase.paused,
      );
    });

    test('normalizeSoundLevel maps the recognizer dB range to 0..1', () {
      expect(VoiceNotifier.normalizeSoundLevel(-2.0), 0.0);
      expect(VoiceNotifier.normalizeSoundLevel(10.0), 1.0);
      expect(VoiceNotifier.normalizeSoundLevel(4.0), 0.5);
      expect(VoiceNotifier.normalizeSoundLevel(-100.0), 0.0); // clamps low
      expect(VoiceNotifier.normalizeSoundLevel(100.0), 1.0); // clamps high
    });

    test('soundLevel resets to 0 when listening stops (setThinking)', () {
      final notifier = container.read(voiceProvider.notifier);
      notifier.startListening();
      notifier.soundLevel.value = 0.7;
      notifier.setThinking();
      expect(notifier.soundLevel.value, 0.0);
    });
  });

  group('SttEngine-driven lifecycle', () {
    late EngineHarness h;
    late FakeTtsEngine tts;
    late FakeBeepChannel beep;
    late ProviderContainer container;

    setUp(() {
      h = EngineHarness();
      tts = FakeTtsEngine(fireCompletionOnSpeak: false);
      beep = FakeBeepChannel();
      container = ProviderContainer(
        overrides: [
          voiceProvider.overrideWith(
            (ref) => VoiceNotifier(
              ref: ref,
              ttsForTesting: tts,
              engineFactory: h.create,
              beepChannelForTesting: beep,
              releaseWakeWordMic: () async {},
              micHandoffDelay: Duration.zero,
              followUpStartDelay: Duration.zero,
            ),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('startListening opens the engine and streams partials', () async {
      final n = c(container);
      n.startListening();
      await pump();
      expect(h.latest!.started, isTrue);
      h.latest!.emitPartial('i had a');
      await pump();
      expect(container.read(voiceProvider).transcript, 'i had a');
      expect(container.read(voiceProvider).micPhase, MicPhase.listening);
    });

    test('opens with exactly one ding per session', () async {
      final n = c(container);
      n.startListening();
      await pump();
      expect(beep.dingCount, 1);
    });

    test('auto-submit stops the engine and moves to thinking', () async {
      final n = c(container);
      n.startListening();
      await pump();
      h.latest!.nextTranscript = 'i had a turkey sandwich';
      h.latest!.fireAutoSubmit();
      await pump();
      expect(
        container.read(voiceProvider).transcript,
        'i had a turkey sandwich',
      );
      expect(container.read(voiceProvider).status, VoiceStatus.thinking);
    });

    test('a partial-less (cloud-style) engine still auto-submits to thinking',
        () async {
      // CloudSttEngine emits no partials (batch); the FakeSttEngine models that
      // when emitPartial is never called. The lifecycle must still complete.
      final n = c(container);
      n.startListening();
      await pump();
      h.latest!.nextTranscript = 'i had an iq bar';
      h.latest!.fireAutoSubmit();
      await pump();
      expect(container.read(voiceProvider).status, VoiceStatus.thinking);
      expect(container.read(voiceProvider).transcript, 'i had an iq bar');
    });

    test('empty transcript does not advance to thinking (no dead spinner)',
        () async {
      // Cloud returns '' on silence/unintelligible audio (ok:true) and has no
      // partials, so advancing would pin a thinking spinner that never replies.
      final n = c(container);
      n.startListening();
      await pump();
      h.latest!.nextTranscript = '';
      h.latest!.fireAutoSubmit();
      await pump();
      expect(container.read(voiceProvider).status, isNot(VoiceStatus.thinking));
      expect(container.read(voiceProvider).micPhase, MicPhase.paused);
    });

    test('a failed cloud transcription drops to manual, not empty thinking',
        () async {
      final n = c(container);
      n.startListening();
      await pump();
      h.latest!.nextResultOk = false; // simulate transcribe failure
      h.latest!.fireAutoSubmit();
      await pump();
      expect(container.read(voiceProvider).status, isNot(VoiceStatus.thinking));
      expect(container.read(voiceProvider).micPhase, MicPhase.paused);
    });

    test('dismiss during submit()\'s stop() leaves the turn cancelled (idle)',
        () async {
      final n = c(container);
      n.startListening();
      await pump();
      h.latest!.nextTranscript = 'i had a turkey sandwich';
      // Auto-submit kicks off submit(); the engine.stop() await is still pending.
      h.latest!.fireAutoSubmit();
      // User taps close before stop() resolves.
      n.dismiss();
      await pump();
      // The cancelled turn must NOT be resurrected into thinking.
      expect(container.read(voiceProvider).status, VoiceStatus.idle);
    });

    test(
      'manual submit() advances to thinking with the final transcript',
      () async {
        final n = c(container);
        n.startListening();
        await pump();
        h.latest!.nextTranscript = 'bloating';
        await n.submit();
        expect(container.read(voiceProvider).status, VoiceStatus.thinking);
        expect(container.read(voiceProvider).transcript, 'bloating');
      },
    );

    test(
      'submit() with no open engine still advances (text-entry path)',
      () async {
        final n = c(container);
        n.setTranscript('typed entry');
        await n.submit();
        expect(container.read(voiceProvider).status, VoiceStatus.thinking);
        expect(container.read(voiceProvider).transcript, 'typed entry');
      },
    );

    // Regression guard for the dispatch-routing bug: a follow-up session must
    // stay in awaitingFollowUp right up until submit, so the overlay routes the
    // answer to sendFollowUpToApi (history/mealId/symptom_followup) — not
    // sendToChat. _openSession must NOT blanket the status to listening.
    test('follow-up session stays awaitingFollowUp until submit', () async {
      final n = c(container);
      n.primeForSymptomFollowUp(mealId: 'm1');
      await pump();
      expect(
        container.read(voiceProvider).status,
        VoiceStatus.awaitingFollowUp,
      );
      h.latest!.emitPartial('a little nauseous');
      await pump();
      // still a follow-up while capturing — not downgraded to listening
      expect(
        container.read(voiceProvider).status,
        VoiceStatus.awaitingFollowUp,
      );
      expect(container.read(voiceProvider).transcript, 'a little nauseous');
    });

    test('primeForSymptomFollowUp does not open mic synchronously; opens '
        'after the orientation delay', () async {
      final n = c(container);
      n.primeForSymptomFollowUp(mealId: 'm1');
      expect(h.creations, 0); // orientation timer has not fired yet
      expect(container.read(voiceProvider).micPhase, MicPhase.preparing);
      expect(
        container.read(voiceProvider).status,
        VoiceStatus.awaitingFollowUp,
      );
      await pump();
      expect(h.creations, 1);
      expect(container.read(voiceProvider).micPhase, MicPhase.listening);
    });

    test(
      'duplicate TTS completions open the follow-up engine only once',
      () async {
        final n = c(container);
        n.setAwaitingFollowUp();
        expect(
          container.read(voiceProvider).status,
          VoiceStatus.awaitingFollowUp,
        );
        n.setAwaitingFollowUp(); // duplicate completion → no-op
        await pump();
        expect(h.creations, 1);
      },
    );
  });

  group('SttEngine-driven lifecycle (custom wiring)', () {
    test(
      'dismiss during the orientation delay cancels the mic start',
      () async {
        final h = EngineHarness();
        final n = VoiceNotifier(
          ttsForTesting: FakeTtsEngine(fireCompletionOnSpeak: false),
          engineFactory: h.create,
          beepChannelForTesting: FakeBeepChannel(),
          releaseWakeWordMic: () async {},
          micHandoffDelay: Duration.zero,
          followUpStartDelay: const Duration(seconds: 10),
        );
        n.primeForSymptomFollowUp(mealId: 'm1');
        n.dismiss();
        await pump();
        expect(h.creations, 0);
        expect(n.state.status, VoiceStatus.idle);
        n.dispose();
      },
    );

    test('dispose cancels a pending follow-up start timer', () async {
      final h = EngineHarness();
      final n = VoiceNotifier(
        ttsForTesting: FakeTtsEngine(fireCompletionOnSpeak: false),
        engineFactory: h.create,
        beepChannelForTesting: FakeBeepChannel(),
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: const Duration(seconds: 10),
      );
      n.primeForSymptomFollowUp(mealId: 'm1');
      n.dispose();
      await pump();
      expect(h.creations, 0);
    });

    test(
      'a failed engine start drops to manual (paused); resume re-opens it',
      () async {
        final h = EngineHarness()..nextThrowOnStart = true;
        final n = VoiceNotifier(
          ttsForTesting: FakeTtsEngine(fireCompletionOnSpeak: false),
          engineFactory: h.create,
          beepChannelForTesting: FakeBeepChannel(),
          releaseWakeWordMic: () async {},
          micHandoffDelay: Duration.zero,
          followUpStartDelay: Duration.zero,
        );
        n.primeForSymptomFollowUp(mealId: 'm1');
        await pump();
        expect(h.creations, 1);
        expect(n.state.micPhase, MicPhase.paused); // fell back to tap-to-talk

        h.nextThrowOnStart = false;
        n.resumeFollowUpListening();
        await pump();
        expect(h.creations, 2);
        expect(n.state.micPhase, MicPhase.listening);
        n.dispose();
      },
    );

    test('on-device model not ready → drops to manual, never blocks/downloads '
        'in the capture path', () async {
      // No engineFactory → real selection. Offline (skip cloud), and a manager
      // that can never be ready (no external dir) → warmDecodeOrNull == null.
      final n = VoiceNotifier(
        ttsForTesting: FakeTtsEngine(fireCompletionOnSpeak: false),
        beepChannelForTesting: FakeBeepChannel(),
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        isOnline: () async => false,
        modelManager: AsrModelManager(externalDir: () async => null),
      );
      n.startListening();
      await pump();
      // Fell back to manual (tap-to-talk / text), no engine adopted.
      expect(n.state.micPhase, MicPhase.paused);
      n.dispose();
    });

    test('hands the wake-word mic off BEFORE opening the engine', () async {
      final h = EngineHarness();
      var creationsAtRelease = -1;
      final n = VoiceNotifier(
        ttsForTesting: FakeTtsEngine(fireCompletionOnSpeak: false),
        engineFactory: h.create,
        beepChannelForTesting: FakeBeepChannel(),
        releaseWakeWordMic: () async {
          creationsAtRelease = h.creations;
        },
        micHandoffDelay: Duration.zero,
      );
      n.startListening();
      await pump();
      expect(creationsAtRelease, 0); // released before any engine was created
      expect(h.creations, 1);
      expect(h.latest!.started, isTrue);
      n.dispose();
    });

    test(
      'follow-up stays "preparing" during handoff, "listening" at capture',
      () async {
        final h = EngineHarness();
        late final VoiceNotifier n;
        MicPhase? phaseAtRelease;
        n = VoiceNotifier(
          ttsForTesting: FakeTtsEngine(fireCompletionOnSpeak: false),
          engineFactory: h.create,
          beepChannelForTesting: FakeBeepChannel(),
          // Handoff runs before the engine starts — capture the UI phase then.
          releaseWakeWordMic: () async {
            phaseAtRelease = n.state.micPhase;
          },
          micHandoffDelay: Duration.zero,
          followUpStartDelay: Duration.zero,
        );
        n.primeForSymptomFollowUp(mealId: 'm1');
        await pump();
        expect(phaseAtRelease, MicPhase.preparing);
        expect(n.state.micPhase, MicPhase.listening);
        n.dispose();
      },
    );
  });

  group('prepareForSpeech', () {
    test('reads digit ranges with dash as "to", not the dash', () {
      expect(
        VoiceNotifier.prepareForSpeech('Any discomfort on a scale of 1–10?'),
        'Any discomfort on a scale of 1 to 10?',
      );
      expect(VoiceNotifier.prepareForSpeech('rate it 1-10'), 'rate it 1 to 10');
      expect(VoiceNotifier.prepareForSpeech('1—10'), '1 to 10');
    });

    test('still reads slash ratings as "out of"', () {
      expect(
        VoiceNotifier.prepareForSpeech('about a 4/10'),
        'about a 4 out of 10',
      );
    });
  });

  group('replyIsQuestion', () {
    test('true only when the reply ends with a question mark', () {
      expect(VoiceNotifier.replyIsQuestion('How are you feeling?'), isTrue);
      expect(VoiceNotifier.replyIsQuestion('Logged it.  '), isFalse);
      expect(VoiceNotifier.replyIsQuestion('Got it, enjoy!'), isFalse);
      expect(VoiceNotifier.replyIsQuestion('Any discomfort 1 to 10? '), isTrue);
    });
  });
}

/// Reads the notifier from a container.
VoiceNotifier c(ProviderContainer container) =>
    container.read(voiceProvider.notifier);
