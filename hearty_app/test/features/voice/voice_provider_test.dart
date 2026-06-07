import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:hearty_app/features/voice/models/voice_state.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';
import 'package:hearty_app/core/audio/audio_beep_channel.dart';
import 'fake_tts_engine.dart';

class FakeBeepChannel implements AudioBeepChannel {
  int suppressCount = 0;
  int restoreCount = 0;
  @override
  Future<void> suppress() async => suppressCount++;
  @override
  Future<void> restore() async => restoreCount++;
}

// Fake SpeechToText for testing
class FakeSpeechToText extends Fake implements SpeechToText {
  bool _isListening = false;
  int listenCount = 0;
  void Function(String)? statusCallback;

  @override
  bool get isListening => _isListening;

  @override
  bool get isNotListening => !_isListening;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #initialize) {
      statusCallback =
          invocation.namedArguments[#onStatus] as void Function(String)?;
      return Future<bool>.value(true);
    }
    if (invocation.memberName == #listen) {
      listenCount++;
      _isListening = true;
      return Future.value();
    }
    if (invocation.memberName == #stop) {
      _isListening = false;
      return Future.value();
    }
    if (invocation.memberName == #cancel) {
      _isListening = false;
      return Future.value();
    }
    return super.noSuchMethod(invocation);
  }
}


void main() {
  group('VoiceNotifier state transitions', () {
    late ProviderContainer container;
    late FakeSpeechToText fakeStt;
    late FakeTtsEngine fakeTts;

    setUp(() {
      fakeStt = FakeSpeechToText();
      fakeTts = FakeTtsEngine();
      container = ProviderContainer(
        overrides: [
          voiceProvider.overrideWith((ref) => VoiceNotifier(
                sttForTesting: fakeStt,
                ttsForTesting: fakeTts,
                releaseWakeWordMic: () async {},
                micHandoffDelay: Duration.zero,
              )),
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
      container.read(voiceProvider.notifier).setResponse('Logged! How are you feeling?');
      expect(container.read(voiceProvider).status, VoiceStatus.responding);
      expect(container.read(voiceProvider).response, 'Logged! How are you feeling?');
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
      expect(s.copyWith(micPhase: MicPhase.listening).micPhase, MicPhase.listening);
      // unspecified copyWith preserves existing value
      expect(s.copyWith(micPhase: MicPhase.paused).copyWith(transcript: 'x').micPhase,
          MicPhase.paused);
    });

    test('primeForSymptomFollowUp does not open mic synchronously; opens after delay', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      // Mic not opened yet; we are in the orientation phase.
      expect(fakeStt.listenCount, 0);
      expect(notifier.state.micPhase, MicPhase.preparing);
      expect(notifier.state.status, VoiceStatus.awaitingFollowUp);
      // Let the zero-delay timer fire.
      await Future<void>.delayed(Duration.zero);
      expect(fakeStt.listenCount, 1);
      expect(notifier.state.micPhase, MicPhase.listening);
      notifier.dispose();
    });

    test('dismiss during the orientation delay cancels the mic start', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: const Duration(seconds: 10),
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      notifier.dismiss();
      await Future<void>.delayed(Duration.zero);
      expect(fakeStt.listenCount, 0);
      expect(notifier.state.status, VoiceStatus.idle);
      notifier.dispose();
    });

    test('dispose cancels a pending follow-up start timer', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: const Duration(seconds: 10),
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      notifier.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(fakeStt.listenCount, 0);
    });

    test('premature notListening with empty transcript does NOT restart; goes paused', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(Duration.zero); // mic opens (listenCount == 1)
      expect(fakeStt.listenCount, 1);

      // Android ends the session before the user said anything.
      fakeStt.statusCallback!(SpeechToText.notListeningStatus);
      await Future<void>.delayed(Duration.zero);

      expect(fakeStt.listenCount, 1); // no restart
      expect(notifier.state.micPhase, MicPhase.paused);
      notifier.dispose();
    });

    test('premature notListening with non-empty transcript DOES restart', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(Duration.zero); // listenCount == 1
      notifier.setTranscript('I feel a bit bloated');

      fakeStt.statusCallback!(SpeechToText.notListeningStatus);
      await Future<void>.delayed(Duration.zero);

      expect(fakeStt.listenCount, 2); // restarted to let them finish
      notifier.dispose();
    });

    test('resumeFollowUpListening opens a session and sets listening', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(Duration.zero);
      fakeStt.statusCallback!(SpeechToText.notListeningStatus); // -> paused
      expect(notifier.state.micPhase, MicPhase.paused);

      notifier.resumeFollowUpListening();
      await Future<void>.delayed(Duration.zero);
      expect(fakeStt.listenCount, 2);
      expect(notifier.state.micPhase, MicPhase.listening);
      notifier.dispose();
    });

    test('duplicate TTS completions arm the follow-up mic only once', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
      );
      // First completion arms the follow-up turn.
      notifier.setAwaitingFollowUp();
      expect(notifier.state.status, VoiceStatus.awaitingFollowUp);
      // A duplicate completion (the ding-storm trigger) must be a no-op.
      notifier.setAwaitingFollowUp();
      // _beginFollowUpStt opens the mic after a 350ms internal delay.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(fakeStt.listenCount, 1); // armed exactly once, not twice
      notifier.dispose();
    });

    test('first follow-up suppresses beep after the delay, dismiss restores', () async {
      final beep = FakeBeepChannel();
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: Duration.zero,
        beepChannelForTesting: beep,
        beepSuppressDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      // Orientation timer -> _beginStt -> arms the beep-suppress timer -> fires.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(beep.suppressCount, 1);
      notifier.dismiss();
      expect(beep.restoreCount, 1);
      notifier.dispose();
    });

    test('dismiss before the suppress delay never suppresses', () async {
      final beep = FakeBeepChannel();
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: Duration.zero,
        beepChannelForTesting: beep,
        beepSuppressDelay: const Duration(seconds: 10),
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(const Duration(milliseconds: 30)); // beginStt arms 10s timer
      notifier.dismiss(); // cancels it
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(beep.suppressCount, 0);
      notifier.dispose();
    });

    test('beep restore is idempotent across multiple exits', () async {
      final beep = FakeBeepChannel();
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {},
        micHandoffDelay: Duration.zero,
        followUpStartDelay: Duration.zero,
        beepChannelForTesting: beep,
        beepSuppressDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(beep.suppressCount, 1);
      notifier.setThinking(); // releases
      notifier.dismiss(); // releases again -> no-op
      expect(beep.restoreCount, 1);
      notifier.dispose();
    });

    test('hands the wake-word mic off BEFORE starting STT', () async {
      var listenCountAtRelease = -1;
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        releaseWakeWordMic: () async {
          listenCountAtRelease = fakeStt.listenCount;
        },
        micHandoffDelay: Duration.zero,
      );
      notifier.startListening();
      await Future<void>.delayed(Duration.zero);
      // Mic was released while STT had not yet started listening...
      expect(listenCountAtRelease, 0);
      // ...and STT did start afterward.
      expect(fakeStt.listenCount, 1);
      notifier.dispose();
    });

    test('follow-up stays "preparing" during handoff, "listening" only at capture', () async {
      late final VoiceNotifier notifier;
      MicPhase? phaseAtRelease;
      notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        // The handoff runs before STT starts — capture the UI phase at that moment.
        releaseWakeWordMic: () async {
          phaseAtRelease = notifier.state.micPhase;
        },
        micHandoffDelay: Duration.zero,
        followUpStartDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(Duration.zero);
      // During the mic handoff the UI must NOT claim to be listening yet...
      expect(phaseAtRelease, MicPhase.preparing);
      // ...it flips to listening only once STT is actually capturing.
      expect(fakeStt.listenCount, 1);
      expect(notifier.state.micPhase, MicPhase.listening);
      notifier.dispose();
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
          VoiceNotifier.prepareForSpeech('about a 4/10'), 'about a 4 out of 10');
    });
  });
}
