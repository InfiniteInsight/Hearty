import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/voice_state.dart';

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  return VoiceNotifier();
});

class VoiceNotifier extends StateNotifier<VoiceState> {
  VoiceNotifier({SpeechToText? sttForTesting, FlutterTts? ttsForTesting})
      : _stt = sttForTesting ?? SpeechToText(),
        _tts = ttsForTesting ?? FlutterTts(),
        super(const VoiceState()) {
    _initTts();
  }

  final SpeechToText _stt;
  final FlutterTts _tts;
  bool _sttInitialized = false;
  bool _askFollowUp = true;

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.9);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (!mounted) return;
      if (_askFollowUp) {
        setAwaitingFollowUp();
      } else {
        dismiss();
      }
    });
  }

  Future<bool> _ensureSttInitialized() async {
    if (!_sttInitialized) {
      _sttInitialized = await _stt.initialize();
    }
    return _sttInitialized;
  }

  void startListening() {
    state = state.copyWith(status: VoiceStatus.listening, transcript: '', response: '');
    _beginStt();
  }

  Future<void> _beginStt() async {
    if (!await _ensureSttInitialized()) return;
    await _stt.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          setTranscript(result.recognizedWords);
        }
        if (result.finalResult) {
          setThinking();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en-US',
    );
  }

  void setTranscript(String text) {
    state = state.copyWith(transcript: text);
  }

  void setThinking() {
    if (_stt.isListening) _stt.stop();
    state = state.copyWith(status: VoiceStatus.thinking);
  }

  /// Sets response text, speaks it via TTS, then transitions to awaitingFollowUp.
  /// Pass [askFollowUp: false] to dismiss after speaking instead.
  void setResponse(String response, {bool askFollowUp = true}) {
    state = state.copyWith(status: VoiceStatus.responding, response: response);
    _speakResponse(response, askFollowUp);
  }

  Future<void> _speakResponse(String response, bool askFollowUp) async {
    _askFollowUp = askFollowUp;
    await _tts.speak(response);
  }

  /// Stops TTS immediately (e.g., user tapped screen) and resets to idle.
  void stopSpeaking() {
    _tts.stop();
    state = const VoiceState();
  }

  void setAwaitingFollowUp() {
    if (!mounted) return;
    state = state.copyWith(status: VoiceStatus.awaitingFollowUp);
    _beginStt();
  }

  void dismiss() {
    if (_stt.isListening) _stt.stop();
    _tts.stop();
    state = const VoiceState();
  }

  /// Phase 5 stub — replaced by real POST /api/chat call in Phase 5.
  /// Pass [defaultAssistantLabel] so non-health queries redirect to the preferred assistant.
  Future<void> simulateApiResponse({String? defaultAssistantLabel}) async {
    final transcript = state.transcript;
    if (transcript.isEmpty) return;
    const nonHealthKeywords = ['weather', 'news', 'music', 'sports', 'stock', 'remind'];
    final isNonHealth = defaultAssistantLabel != null &&
        nonHealthKeywords.any((k) => transcript.toLowerCase().contains(k));
    if (isNonHealth) {
      await redirectToAssistant(defaultAssistantLabel);
    } else {
      setResponse('Got it! I logged "$transcript". How are you feeling?');
    }
  }

  /// Speaks the redirect response for a non-health query.
  Future<void> redirectToAssistant(String assistantLabel) async {
    final response = assistantLabel == 'None'
        ? "That's outside what I track. I focus on food, symptoms, and wellbeing."
        : 'For that, try asking $assistantLabel.';
    setResponse(response, askFollowUp: false);
  }

  @override
  void dispose() {
    _stt.stop();
    _tts.stop();
    super.dispose();
  }
}
