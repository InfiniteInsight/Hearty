import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hearty_app/features/voice/models/voice_state.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';
import 'package:hearty_app/core/audio/audio_beep_channel.dart';
import 'package:hearty_app/core/stt/stt_engine.dart';
import 'package:hearty_app/core/stt/asr_model_manager.dart';
import 'package:hearty_app/core/stt/on_device_model.dart';
import 'package:hearty_app/core/api/models/user_preferences.dart';
import 'package:hearty_app/core/api/providers/preferences_provider.dart';
import 'fake_tts_engine.dart';
import '../../core/stt/fake_stt_engine.dart';

/// Records call patterns and simulates a cold→warm transition so the
/// warm-on-demand path (#18) can be exercised without native sherpa/mic.
class _FakeModelManager extends AsrModelManager {
  _FakeModelManager({required this.downloaded});
  final bool downloaded;
  int warmDecodeCalls = 0;
  int isReadyCalls = 0;
  int ensureCalls = 0;

  // Always reports cold (warmDecodeOrNull == null). We deliberately never flip
  // to warm: a warm result makes _selectEngine build a real OnDeviceBatchSttEngine
  // whose native `record` mic can't run in a unit test. Reporting cold both
  // before AND after the warm lets us assert the *decision* the fix makes — does
  // it check isReady, await the warm, and re-check the decoder — without needing
  // the native engine. The success-then-listen path is verified on-device (#18).
  @override
  Future<String> Function(Float32List)? warmDecodeOrNull(OnDeviceModel model) {
    warmDecodeCalls++;
    return null;
  }

  @override
  Future<bool> isReady(OnDeviceModel model) async {
    isReadyCalls++;
    return downloaded;
  }

  @override
  Future<void> ensureAndWarm(OnDeviceModel model,
      {void Function(double progress)? onProgress}) async {
    ensureCalls++;
  }
}

/// Seeds [preferencesProvider] with fixed prefs so engine selection / capture
/// config read real user settings instead of the test DB.
class _SeedPrefs extends PreferencesNotifier {
  _SeedPrefs(this._seed);
  final UserPreferences _seed;
  @override
  Future<UserPreferences> build() async => _seed;
}

const _defaultPrefs = UserPreferences();

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
          // Seed prefs so the capture path's pref reads (auto-submit, model,
          // cloud) don't spin up the real drift DB / platform channels.
          preferencesProvider.overrideWith(() => _SeedPrefs(_defaultPrefs)),
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

    test('TTS completion fired AFTER dismiss does not open a ghost session',
        () async {
      final n = container.read(voiceProvider.notifier);
      // Hearty is speaking a response that would normally ask a follow-up.
      n.setResponse('Logged! How are you feeling?');
      expect(n.state.status, VoiceStatus.responding);
      final before = h.creations;
      // User taps X mid-response. dismiss() stops TTS, which in production fires
      // the completion callback — simulate that arriving after the cancel.
      n.dismiss();
      expect(n.state.status, VoiceStatus.idle);
      tts.fireCompletion();
      await pump();
      // No capture session was opened, and we stayed idle (no resurrected turn
      // fighting the wake-word mic).
      expect(h.creations, before);
      expect(n.state.status, VoiceStatus.idle);
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
          // Seed prefs so the capture path's pref reads (auto-submit, model,
          // cloud) don't spin up the real drift DB / platform channels.
          preferencesProvider.overrideWith(() => _SeedPrefs(_defaultPrefs)),
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

    test('engine amplitude drives soundLevel and resets on stop (#13)', () async {
      final n = c(container);
      n.startListening();
      await pump();
      // Raw linear RMS flows through untouched (no dB remap).
      h.latest!.emitAmplitude(0.08);
      await pump();
      expect(n.soundLevel.value, 0.08);
      // Auto-submit ends capture → prism drops back to a calm beam.
      h.latest!.nextTranscript = 'pizza';
      h.latest!.fireAutoSubmit();
      await pump();
      expect(n.soundLevel.value, 0.0);
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

    test('strips markdown emphasis so the symbols are not spoken', () {
      expect(
        VoiceNotifier.prepareForSpeech('That was **important** to note'),
        'That was important to note',
      );
      expect(VoiceNotifier.prepareForSpeech('a *little* `code` ~~gone~~'),
          'a little code gone');
    });

    test('reads "IV" as the letters, not the word "I\'ve"', () {
      expect(VoiceNotifier.prepareForSpeech('You logged Liquid IV'),
          'You logged Liquid I.V.');
      expect(VoiceNotifier.prepareForSpeech('after the IV. drip'),
          'after the I.V. drip');
      // Doesn't mangle ordinary words that merely contain "iv".
      expect(VoiceNotifier.prepareForSpeech('give it a rest'),
          'give it a rest');
    });

    test('combines markdown + IV + range cleanup', () {
      expect(
        VoiceNotifier.prepareForSpeech('**Liquid IV** rated 1-10'),
        'Liquid I.V. rated 1 to 10',
      );
    });
  });

  group('stripMarkdown', () {
    test('removes emphasis markers, keeps words, collapses spaces', () {
      expect(VoiceNotifier.stripMarkdown('**bold** and *italic*'),
          'bold and italic');
      expect(VoiceNotifier.stripMarkdown('plain text'), 'plain text');
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

  // Proves the Settings auto-submit toggle isn't dead UI: the capture session
  // actually gates onAutoSubmit on the live pref (not just the constructor
  // default). Without the _effectiveAutoSubmit wiring the slider/toggle would
  // persist a value nothing consumes.
  group('auto-submit pref consumption', () {
    late EngineHarness h;
    ProviderContainer makeContainer(UserPreferences seed) {
      h = EngineHarness();
      return ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(() => _SeedPrefs(seed)),
          voiceProvider.overrideWith(
            (ref) => VoiceNotifier(
              ref: ref,
              ttsForTesting: FakeTtsEngine(fireCompletionOnSpeak: false),
              engineFactory: h.create,
              beepChannelForTesting: FakeBeepChannel(),
              releaseWakeWordMic: () async {},
              micHandoffDelay: Duration.zero,
              followUpStartDelay: Duration.zero,
            ),
          ),
        ],
      );
    }

    test('autoSubmit:true → engine started WITH an onAutoSubmit callback',
        () async {
      final container = makeContainer(const UserPreferences(autoSubmit: true));
      addTearDown(container.dispose);
      // Realize the seeded prefs so valueOrNull is populated before the session.
      await container.read(preferencesProvider.future);
      c(container).startListening();
      await pump();
      expect(h.latest!.autoSubmit, isNotNull);
    });

    test('autoSubmit:false → engine started WITHOUT an onAutoSubmit callback',
        () async {
      final container = makeContainer(const UserPreferences(autoSubmit: false));
      addTearDown(container.dispose);
      await container.read(preferencesProvider.future);
      c(container).startListening();
      await pump();
      expect(h.latest!.autoSubmit, isNull);
    });
  });

  group('on-device warm-on-demand (#18)', () {
    ProviderContainer makeContainer(_FakeModelManager mgr) => ProviderContainer(
          overrides: [
            preferencesProvider.overrideWith(() => _SeedPrefs(_defaultPrefs)),
            voiceProvider.overrideWith(
              (ref) => VoiceNotifier(
                ref: ref,
                ttsForTesting: FakeTtsEngine(fireCompletionOnSpeak: false),
                beepChannelForTesting: FakeBeepChannel(),
                releaseWakeWordMic: () async {},
                micHandoffDelay: Duration.zero,
                modelManager: mgr,
                isOnline: () async => false, // force the on-device branch
                // no engineFactory → exercises the real _selectEngine
              ),
            ),
          ],
        );

    test('cold-but-downloaded model warms on demand and re-checks the decoder',
        () async {
      // The bug: first tap finds the warm isolate idle-released, so the old
      // code threw SttNotReadyException immediately → manual, forcing a second
      // tap. The fix: when the model is on disk, await the warm and re-check the
      // decoder (then build the engine + listen — that last step is verified
      // on-device, since it needs the native mic). Here the fake stays cold, so
      // we assert the decision: isReady checked, warm awaited, decoder re-read.
      final mgr = _FakeModelManager(downloaded: true);
      final container = makeContainer(mgr);
      addTearDown(container.dispose);
      await container.read(preferencesProvider.future);

      container.read(voiceProvider.notifier).startListening();
      await pump(20);

      expect(mgr.isReadyCalls, greaterThan(0),
          reason: 'cold path must check whether the model is downloaded');
      expect(mgr.ensureCalls, greaterThan(0),
          reason: 'must await the warm on demand, not skip it');
      expect(mgr.warmDecodeCalls, greaterThanOrEqualTo(2),
          reason: 're-reads the decoder after warming (vs old immediate throw)');
    });

    test('not-downloaded model does NOT block (background fetch, manual now)',
        () async {
      // A model that still needs a multi-minute download must not be awaited on
      // the capture path — it stays the old behavior: kick off the fetch, drop
      // to manual immediately (no warm re-check).
      final mgr = _FakeModelManager(downloaded: false);
      final container = makeContainer(mgr);
      addTearDown(container.dispose);
      await container.read(preferencesProvider.future);

      container.read(voiceProvider.notifier).startListening();
      await pump(20);

      expect(mgr.isReadyCalls, greaterThan(0));
      expect(mgr.ensureCalls, greaterThan(0),
          reason: 'background fetch is still kicked off');
      expect(mgr.warmDecodeCalls, 1,
          reason: 'not-downloaded path throws without re-checking the decoder');
      expect(container.read(voiceProvider).micPhase, MicPhase.paused,
          reason: 'drops to manual for this turn');
    });
  });
}

/// Reads the notifier from a container.
VoiceNotifier c(ProviderContainer container) =>
    container.read(voiceProvider.notifier);
