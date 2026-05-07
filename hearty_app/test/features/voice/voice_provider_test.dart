import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hearty_app/features/voice/models/voice_state.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';

// Fake SpeechToText for testing
class FakeSpeechToText extends Fake implements SpeechToText {
  bool _isListening = false;

  @override
  bool get isListening => _isListening;

  @override
  bool get isNotListening => !_isListening;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #initialize) {
      return Future<bool>.value(true);
    }
    if (invocation.memberName == #listen) {
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

// Fake FlutterTts for testing
class FakeFlutterTts extends Fake implements FlutterTts {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setLanguage) {
      return Future<int>.value(1);
    }
    if (invocation.memberName == #setSpeechRate) {
      return Future.value();
    }
    if (invocation.memberName == #setPitch) {
      return Future.value();
    }
    if (invocation.memberName == #speak) {
      return Future<int>.value(1);
    }
    if (invocation.memberName == #stop) {
      return Future.value();
    }
    if (invocation.memberName == #setCompletionHandler) {
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('VoiceNotifier state transitions', () {
    late ProviderContainer container;
    late FakeSpeechToText fakeStt;
    late FakeFlutterTts fakeTts;

    setUp(() {
      fakeStt = FakeSpeechToText();
      fakeTts = FakeFlutterTts();
      container = ProviderContainer(
        overrides: [
          voiceProvider.overrideWith((ref) => VoiceNotifier(sttForTesting: fakeStt, ttsForTesting: fakeTts)),
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
  });
}
