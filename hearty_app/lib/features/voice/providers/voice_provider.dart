import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/voice_state.dart';

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  return VoiceNotifier();
});

class VoiceNotifier extends StateNotifier<VoiceState> {
  VoiceNotifier({SpeechToText? sttForTesting})
      : _stt = sttForTesting ?? SpeechToText(),
        super(const VoiceState());

  final SpeechToText _stt;
  bool _sttInitialized = false;

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

  void setResponse(String response) {
    state = state.copyWith(status: VoiceStatus.responding, response: response);
  }

  void setAwaitingFollowUp() {
    state = state.copyWith(status: VoiceStatus.awaitingFollowUp);
    _beginStt();
  }

  void dismiss() {
    if (_stt.isListening) _stt.stop();
    state = const VoiceState();
  }

  @override
  void dispose() {
    _stt.stop();
    super.dispose();
  }
}
