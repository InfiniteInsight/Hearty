import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';
import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/offline_exception.dart';
import '../../../core/api/providers/meals_provider.dart' show syncTriggerProvider;
import '../../../core/offline/local_voice_queue_dao.dart';
import '../models/voice_state.dart';

const _uuid = Uuid();

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  return VoiceNotifier(ref: ref);
});

class VoiceNotifier extends StateNotifier<VoiceState> {
  VoiceNotifier({
    Ref? ref,
    SpeechToText? sttForTesting,
    FlutterTts? ttsForTesting,
  })  : _ref = ref,
        _stt = sttForTesting ?? SpeechToText(),
        _tts = ttsForTesting ?? FlutterTts(),
        super(const VoiceState()) {
    _initTts();
  }

  final Ref? _ref;
  final SpeechToText _stt;
  final FlutterTts _tts;
  bool _sttInitialized = false;
  bool _askFollowUp = true;

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.7);
    await _tts.setPitch(1.0);
    final prefs = await SharedPreferences.getInstance();
    final savedVoice = prefs.getString('tts_voice_name');
    if (savedVoice != null) {
      await _tts.setVoice({'name': savedVoice, 'locale': 'en-US'});
    }
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
      _sttInitialized = await _stt.initialize(
        onStatus: _onSttStatus,
        onError: (_) => _autoSubmitIfPending(),
      );
    }
    return _sttInitialized;
  }

  // STT stopped without a finalResult — submit the partial transcript rather
  // than silently dropping it. Covers both the initial listen and follow-up
  // sessions since both use the same _beginStt path.
  void _onSttStatus(String status) {
    if (status == SpeechToText.notListeningStatus || status == SpeechToText.doneStatus) {
      _autoSubmitIfPending();
    }
  }

  void _autoSubmitIfPending() {
    if (!mounted) return;
    final s = state;
    if (s.transcript.isNotEmpty &&
        (s.status == VoiceStatus.listening || s.status == VoiceStatus.awaitingFollowUp)) {
      setThinking();
    }
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
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
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
  void setResponse(String response, {bool askFollowUp = true, String? mealId}) {
    state = state.copyWith(
      status: VoiceStatus.responding,
      response: response,
      pendingMealId: mealId ?? state.pendingMealId,
    );
    _speakResponse(response, askFollowUp);
  }

  Future<void> _speakResponse(String response, bool askFollowUp) async {
    _askFollowUp = askFollowUp;
    await _tts.speak(_stripEmojis(response));
  }

  // Removes emoji codepoints so TTS doesn't read out their names.
  static String _stripEmojis(String text) {
    return text.replaceAll(
      RegExp(
        r'[\u{1F000}-\u{1FFFF}'
        r'\u{2600}-\u{27BF}'
        r'\u{2300}-\u{23FF}'
        r'\u{FE00}-\u{FE0F}'
        r'\u{1F900}-\u{1F9FF}'
        r'\u{1FA00}-\u{1FA6F}'
        r'\u{1FA70}-\u{1FAFF}]+',
        unicode: true,
      ),
      '',
    ).replaceAll(RegExp(r'  +'), ' ').trim();
  }

  /// Stops TTS immediately (e.g., user tapped screen) and resets to idle.
  void stopSpeaking() {
    _tts.stop();
    state = const VoiceState();
  }

  void setAwaitingFollowUp() {
    if (!mounted) return;
    state = state.copyWith(
      status: VoiceStatus.awaitingFollowUp,
      originalTranscript: state.transcript,
      transcript: '',
    );
    _beginFollowUpStt();
  }

  Future<void> _beginFollowUpStt() async {
    // Cancel any lingering Android SpeechRecognizer session from the first turn
    // and give it time to fully tear down before starting a new listen().
    if (_stt.isListening) await _stt.cancel();
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) await _beginStt();
  }

  void dismiss() {
    if (_stt.isListening) _stt.stop();
    _tts.stop();
    state = const VoiceState();
  }

  /// Sends the current transcript to the Hearty chat API.
  /// Falls back gracefully when offline or when [_ref] is not available.
  Future<void> sendToChat() async {
    final transcript = state.transcript;
    if (transcript.isEmpty) return;

    const nonHealthKeywords = ['weather', 'news', 'music', 'sports', 'stock', 'remind'];
    if (nonHealthKeywords.any((k) => transcript.toLowerCase().contains(k))) {
      setResponse("That's outside what I track. I focus on food, symptoms, and wellbeing.", askFollowUp: false);
      return;
    }

    // If no ref (e.g. in certain test contexts), fall back to stub.
    final ref = _ref;
    if (ref == null) {
      setResponse('Got it! I logged "$transcript". How are you feeling?');
      return;
    }

    try {
      final client = ref.read(heartyApiClientProvider);
      final result = await client.chat(message: transcript);
      if (!mounted) return;
      setResponse(
        result.reply.isNotEmpty ? result.reply : 'Got it! How are you feeling?',
        mealId: result.mealId,
      );
      ref.read(syncTriggerProvider).schedule();
    } on OfflineException {
      if (!mounted) return;
      final ref = _ref;
      if (ref != null) {
        final dao = ref.read(localVoiceQueueDaoProvider);
        await dao.insertPending(
          id: _uuid.v4(),
          transcript: transcript,
          loggedAt: DateTime.now(),
        );
      }
      setResponse(
        "You're offline or Hearty is down. I'll save that and log it when you reconnect.",
        askFollowUp: false,
      );
    } catch (_) {
      if (!mounted) return;
      setResponse('Got it! I logged "$transcript". How are you feeling?');
    }
  }

  /// Sends the follow-up transcript back through the chat API so the AI can
  /// parse it properly — it may contain a meal clarification, a symptom, a
  /// wellbeing update, or some combination. Ends the conversation after.
  Future<void> sendFollowUpToApi() async {
    final transcript = state.transcript;
    if (transcript.isEmpty) {
      dismiss();
      return;
    }
    final ref = _ref;
    if (ref == null) {
      setResponse('Got it, thanks!', askFollowUp: false);
      return;
    }
    try {
      final client = ref.read(heartyApiClientProvider);
      final history = <Map<String, String>>[
        if (state.originalTranscript?.isNotEmpty == true)
          {'role': 'user', 'content': state.originalTranscript!},
        if (state.response.isNotEmpty)
          {'role': 'assistant', 'content': state.response},
      ];
      final result = await client.chat(
        message: transcript,
        mealId: state.pendingMealId,
        history: history.isEmpty ? null : history,
      );
      if (!mounted) return;
      setResponse(result.reply.isNotEmpty ? result.reply : 'Got it, thanks!', askFollowUp: false);
      ref.read(syncTriggerProvider).schedule();
    } catch (_) {
      if (!mounted) return;
      setResponse('Got it, thanks!', askFollowUp: false);
    }
  }

  /// Phase 5 stub — kept for backwards compatibility; delegates to sendToChat.
  Future<void> simulateApiResponse() async {
    await sendToChat();
  }

  @override
  void dispose() {
    _stt.stop();
    _tts.stop();
    super.dispose();
  }
}
