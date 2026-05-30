import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';
import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/offline_exception.dart';
import '../../../core/api/providers/last_logged_provider.dart';
import '../../../core/api/providers/meals_provider.dart' show syncTriggerProvider;
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/notifications/notification_service.dart';
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
  // Follow-up STT state — Android fires notListening after its own short
  // silence timeout, ignoring pauseFor. We restart up to _maxFollowUpRestarts
  // times and accumulate the transcript across sessions.
  bool _inFollowUpListen = false;
  int _followUpRestarts = 0;
  String _followUpAccumulated = '';
  static const int _maxFollowUpRestarts = 3;
  bool _useDictation = true; // try dictation mode first; falls back on error

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
        onError: _onSttError,
      );
    }
    return _sttInitialized;
  }

  void _onSttError(dynamic error) {
    if (_inFollowUpListen && _useDictation) {
      // Dictation mode failed (no network or unsupported) — retry in command mode.
      _useDictation = false;
      _inFollowUpListen = false;
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
          _beginStt(isFollowUp: true);
        }
      });
    } else {
      _autoSubmitIfPending();
    }
  }

  void _onSttStatus(String status) {
    if (status == SpeechToText.notListeningStatus || status == SpeechToText.doneStatus) {
      if (_inFollowUpListen &&
          _followUpRestarts < _maxFollowUpRestarts &&
          mounted &&
          state.status == VoiceStatus.awaitingFollowUp) {
        // Android ended the session prematurely — restart so the user can
        // finish their thought. Accumulate what was captured so far.
        _followUpAccumulated = state.transcript;
        _followUpRestarts++;
        _beginStt(isFollowUp: true);
        return;
      }
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
    state = const VoiceState(status: VoiceStatus.listening);
    _beginStt();
  }

  /// Opens the overlay in follow-up mode with Hearty's symptom question
  /// already showing, mic active, no TTS. [mealId] links the response to the
  /// meal that triggered the nudge notification.
  void primeForSymptomFollowUp({String? mealId}) {
    // Stop any in-progress audio from a previous session. Calling
    // _stt.listen() while already listening silently fails on Android.
    if (_stt.isListening) _stt.stop();
    _tts.stop();

    // Reset follow-up STT accumulators. If a previous session hit the
    // max-restart limit, the counter would stay at 3 and prevent retries.
    _inFollowUpListen = false;
    _followUpRestarts = 0;
    _followUpAccumulated = '';
    _useDictation = true;

    const question =
        'How are you feeling after your last meal? Let me know about any discomfort — you can rate it 1–10, or just say you\'re feeling good.';
    state = VoiceState(
      status: VoiceStatus.awaitingFollowUp,
      response: question,
      pendingMealId: mealId,
      history: const [
        {'role': 'assistant', 'content': question}
      ],
    );
    _beginStt(isFollowUp: true);
  }

  Future<void> _beginStt({bool isFollowUp = false}) async {
    _inFollowUpListen = isFollowUp;
    if (!await _ensureSttInitialized()) return;
    final mode = isFollowUp && _useDictation
        ? ListenMode.dictation
        : ListenMode.confirmation;
    await _stt.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          final words = result.recognizedWords;
          // When Android hands the restarted session buffered audio, `words`
          // can be a superset of `_followUpAccumulated`. Detect that and use
          // `words` directly so the transcript is not duplicated.
          final combined = _followUpAccumulated.isNotEmpty
              ? (words.startsWith(_followUpAccumulated.trim())
                  ? words
                  : '$_followUpAccumulated $words')
              : words;
          setTranscript(combined);
        }
        if (result.finalResult) {
          if (_inFollowUpListen && _followUpRestarts < _maxFollowUpRestarts) {
            // Android fired finalResult early — save what we have and restart.
            _followUpAccumulated = state.transcript;
            _followUpRestarts++;
            _inFollowUpListen = false;
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
                _beginStt(isFollowUp: true);
              }
            });
          } else {
            setThinking();
          }
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 8),
      localeId: 'en-US',
      listenOptions: SpeechListenOptions(listenMode: mode),
    );
  }

  void setTranscript(String text) {
    state = state.copyWith(transcript: text);
  }

  void setThinking() {
    _inFollowUpListen = false;
    _followUpRestarts = 0;
    _followUpAccumulated = '';
    _useDictation = true;
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
    await _tts.speak(_prepareForSpeech(response));
  }

  static String _prepareForSpeech(String text) {
    text = _stripEmojis(text);
    // "4/10" → "4 out of 10" so TTS doesn't read it as a fraction
    text = text.replaceAllMapped(
      RegExp(r'(\d+)/(\d+)'),
      (m) => '${m[1]} out of ${m[2]}',
    );
    return text;
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
    final updatedHistory = [
      ...state.history,
      if (state.transcript.isNotEmpty) {'role': 'user', 'content': state.transcript},
      if (state.response.isNotEmpty) {'role': 'assistant', 'content': state.response},
    ];
    state = state.copyWith(
      status: VoiceStatus.awaitingFollowUp,
      history: updatedHistory,
      transcript: '',
    );
    _beginFollowUpStt();
  }

  Future<void> _beginFollowUpStt() async {
    _followUpRestarts = 0;
    _followUpAccumulated = '';
    _useDictation = true;
    // Cancel any lingering Android SpeechRecognizer session from the first turn
    // and give it time to fully tear down before starting a new listen().
    if (_stt.isListening) await _stt.cancel();
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) await _beginStt(isFollowUp: true);
  }

  void dismiss() {
    if (_stt.isListening) _stt.stop();
    _tts.stop();
    state = const VoiceState();
  }

  static bool _isOffTopic(String transcript) {
    var t = transcript.toLowerCase().trim();

    // Fast-path: unambiguous journal-entry openers → never off-topic.
    const journalPrefixes = [
      'i ate', 'i had', 'i drank', "i'm eating", "i'm having",
      "i'm feeling", 'i feel', "i've been", 'i just', 'i noticed',
    ];
    if (journalPrefixes.any((p) => t.startsWith(p))) return false;

    // Rising-intonation question mark.
    if (t.endsWith('?')) return true;

    // Strip leading assistant-command prefixes so "can you tell me..."
    // is caught by the same startsWith rules as bare "tell me...".
    const stripPrefixes = ['can you ', 'could you ', 'would you '];
    for (final p in stripPrefixes) {
      if (t.startsWith(p)) {
        t = t.substring(p.length);
        break;
      }
    }

    // Question / command starters.
    const startsWithBlocked = [
      'who ', 'what ', 'where ', 'why ',
      'when did ', 'when is ', 'when was ', 'when are ',
      'how do ', 'how can ', 'how would ', 'how to ', 'how does ',
      'tell me', 'explain', 'help me with',
      'write me', 'write a', 'draft',
      'call ', 'play ', 'text ',
    ];
    if (startsWithBlocked.any((p) => t.startsWith(p))) return true;

    // Phrases that are off-topic regardless of sentence position.
    const anywhereBlocked = [
      'weather', 'news', 'music', 'sports', 'stock', 'remind',
      'homework', 'movie', 'film', 'joke', 'trivia', 'calculate',
      'find me', 'look up', 'search for', 'teach me',
      'show me how', 'set a timer', 'set a reminder',
    ];
    if (anywhereBlocked.any((p) => t.contains(p))) return true;

    return false;
  }

  /// Sends the current transcript to the Hearty chat API.
  /// Falls back gracefully when offline or when [_ref] is not available.
  Future<void> sendToChat() async {
    final transcript = state.transcript;
    if (transcript.isEmpty) return;

    if (_isOffTopic(transcript)) {
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
      final prefs = ref.read(preferencesProvider).valueOrNull;
      final result = await client.chat(
        message: transcript,
        conversationStyle: prefs?.conversationStyle ?? 'warm',
      );
      if (!mounted) return;
      setResponse(
        result.reply.isNotEmpty ? result.reply : 'Got it! How are you feeling?',
        mealId: result.mealId,
      );
      if (result.mealId != null) {
        ref.read(lastLoggedMealIdProvider.notifier).state = result.mealId;
        final sharedPrefs = await SharedPreferences.getInstance();
        await sharedPrefs.setString('hearty_last_meal_id', result.mealId!);
        if (prefs != null && prefs.postMealNudgeEnabled) {
          await NotificationService.scheduleFollowUpNotification(prefs.nudgeDelayMinutes);
        }
      }
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

  /// Sends the follow-up transcript back through the chat API. Keeps the
  /// conversation open if Hearty's reply ends with a question.
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
      final result = await client.chat(
        message: transcript,
        mealId: state.pendingMealId,
        history: state.history.isEmpty ? null : state.history,
        conversationStyle: ref.read(preferencesProvider).valueOrNull?.conversationStyle ?? 'warm',
      );
      if (!mounted) return;
      final reply = result.reply.isNotEmpty ? result.reply : 'Got it, thanks!';
      final keepGoing = reply.trimRight().endsWith('?');
      setResponse(reply, askFollowUp: keepGoing);
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
