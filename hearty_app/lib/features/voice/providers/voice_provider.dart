import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';
import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/offline_exception.dart';
import '../../../core/api/providers/last_logged_provider.dart';
import '../../../core/api/providers/meals_provider.dart' show syncTriggerProvider;
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/audio/audio_beep_channel.dart';
import '../../../core/offline/local_voice_queue_dao.dart';
import '../../../core/tts/tts_engine.dart';
import '../../../core/tts/tts_engine_factory.dart';
import '../../wake_word/wake_word_channel.dart';
import '../models/voice_state.dart';

const _uuid = Uuid();

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  return VoiceNotifier(ref: ref);
});

class VoiceNotifier extends StateNotifier<VoiceState> {
  VoiceNotifier({
    Ref? ref,
    SpeechToText? sttForTesting,
    TtsEngine? ttsForTesting,
    Duration? followUpStartDelay,
    AudioBeepChannel? beepChannelForTesting,
    Duration? beepSuppressDelay,
    Future<void> Function()? releaseWakeWordMic,
    Duration? micHandoffDelay,
  })  : _ref = ref,
        _stt = sttForTesting ?? SpeechToText(),
        _injectedTts = ttsForTesting,
        _followUpStartDelay =
            followUpStartDelay ?? const Duration(milliseconds: 2500),
        _beep = beepChannelForTesting ?? AudioBeepChannel(),
        _beepSuppressDelay =
            beepSuppressDelay ?? const Duration(milliseconds: 800),
        _releaseWakeWordMic =
            releaseWakeWordMic ?? WakeWordChannel.stopListening,
        _micHandoffDelay =
            micHandoffDelay ?? const Duration(milliseconds: 250),
        super(const VoiceState()) {
    _ready = _initTts();
  }

  final Ref? _ref;
  final SpeechToText _stt;
  final TtsEngine? _injectedTts;
  late TtsEngine _tts;
  late final Future<void> _ready;
  bool _sttInitialized = false;
  bool _askFollowUp = true;
  // Follow-up STT state — Android fires notListening after its own short
  // silence timeout, ignoring pauseFor. We restart up to _maxFollowUpRestarts
  // times and accumulate the transcript across sessions — but only once the
  // user has actually started speaking (see _onSttStatus), so pre-speech
  // silence does not churn through restarts (each restart plays a beep).
  bool _inFollowUpListen = false;
  // True while in the post-meal symptom check-in (started by the nudge). Tells
  // the backend this turn is a "how are you feeling?" response about an
  // already-logged meal so it never edits the meal (see symptom_followup).
  bool _symptomCheckIn = false;
  int _followUpRestarts = 0;
  String _followUpAccumulated = '';
  static const int _maxFollowUpRestarts = 3;
  bool _useDictation = true; // try dictation mode first; falls back on error
  // Orientation delay before the follow-up mic opens, so the user can read the
  // question first. Cancelable via dismiss(); injectable for tests.
  final Duration _followUpStartDelay;
  Timer? _followUpStartTimer;
  // Beep suppression: let the first follow-up beep play, then mute the
  // recognizer beep streams so the restart sessions are silent. Released via
  // _releaseBeepSuppression() on every exit path so it can never leak.
  final AudioBeepChannel _beep;
  final Duration _beepSuppressDelay;
  Timer? _beepSuppressTimer;
  bool _beepSuppressed = false;
  // The always-on wake-word foreground service holds the microphone (an
  // AudioRecord on VOICE_RECOGNITION). On Android the existing capture client
  // wins, so SpeechRecognizer is starved and hears nothing unless we hand the
  // mic off first — exactly what the native onWakeWordDetected() does for the
  // wake-word path. We mirror that for every STT session and re-arm the service
  // when the voice overlay closes (VoiceOverlayScreen.dispose). _micHandoffDelay
  // gives the audio HAL a beat to release the input before SpeechRecognizer
  // grabs it. Injectable so unit tests stay synchronous and timer-free.
  final Future<void> Function() _releaseWakeWordMic;
  final Duration _micHandoffDelay;
  // Once the wake-word mic is handed off for a session it stays released until
  // the overlay closes (re-armed in VoiceOverlayScreen.dispose). So we only pay
  // the settle delay on the first listen of a session — restarts re-acquire
  // immediately, avoiding a dead window mid-speech. Reset at each session start.
  bool _wakeWordMicReleased = false;
  // Live mic amplitude (0..1) for the prism visualiser, updated from the STT
  // recognizer's onSoundLevelChange while listening; reset to 0 when listening
  // stops so the beam settles. The painter's gate + smoothing shape the look.
  final ValueNotifier<double> soundLevel = ValueNotifier<double>(0.0);

  /// Maps the recognizer's rms-dB-ish sound level (~-2 silence .. ~10 loud,
  /// per Android's onRmsChanged range) to a 0..1 amplitude for the visualiser.
  static double normalizeSoundLevel(double raw) =>
      ((raw + 2.0) / 12.0).clamp(0.0, 1.0);

  Future<void> _initTts() async {
    _tts = _injectedTts ?? await createTtsEngine();
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
      _releaseBeepSuppression();
      _autoSubmitIfPending();
    }
  }

  void _onSttStatus(String status) {
    if (status == SpeechToText.notListeningStatus || status == SpeechToText.doneStatus) {
      if (_inFollowUpListen &&
          state.transcript.isNotEmpty &&
          _followUpRestarts < _maxFollowUpRestarts &&
          mounted &&
          state.status == VoiceStatus.awaitingFollowUp) {
        // The user started talking and Android ended the session early —
        // restart so they can finish. Accumulate what was captured so far.
        _followUpAccumulated = state.transcript;
        _followUpRestarts++;
        _beginStt(isFollowUp: true);
        return;
      }
      if (_inFollowUpListen &&
          state.transcript.isEmpty &&
          mounted &&
          state.status == VoiceStatus.awaitingFollowUp) {
        // Nothing captured yet — don't churn through restarts (each restart
        // beeps). Go idle and let the user tap to talk when ready.
        _pauseFollowUpMic();
        return;
      }
      // Android frequently fires notListening/done a beat BEFORE the final
      // recognition result lands. Submitting immediately ships a truncated
      // transcript (e.g. "I had" instead of "I had an Oreo"). Defer the
      // auto-submit so the finalResult can arrive first — finalResult calls
      // setThinking, which moves us out of listening and no-ops this fallback.
      Future.delayed(const Duration(milliseconds: 700), () {
        _autoSubmitIfPending();
      });
    }
  }

  void _pauseFollowUpMic() {
    _releaseBeepSuppression();
    _inFollowUpListen = false;
    soundLevel.value = 0.0;
    if (mounted) state = state.copyWith(micPhase: MicPhase.paused);
  }

  void _releaseBeepSuppression() {
    _beepSuppressTimer?.cancel();
    if (_beepSuppressed) {
      _beep.restore();
      _beepSuppressed = false;
    }
  }

  /// Re-opens one follow-up listen session — wired to the overlay's
  /// "Tap to talk" button after the mic went idle on pre-speech silence.
  void resumeFollowUpListening() {
    if (state.micPhase != MicPhase.paused) return;
    _beginStt(isFollowUp: true);
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
    // Release any lingering follow-up beep suppression when a fresh session
    // starts, so the "released on every exit" invariant holds unconditionally.
    _releaseBeepSuppression();
    // A fresh manual/wake-word session is a normal meal log, not a check-in.
    _symptomCheckIn = false;
    _wakeWordMicReleased = false; // new session — wake-word mic is armed again
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
    _stopTts();

    // Reset follow-up STT accumulators. If a previous session hit the
    // max-restart limit, the counter would stay at 3 and prevent retries.
    _inFollowUpListen = false;
    _followUpRestarts = 0;
    _followUpAccumulated = '';
    _useDictation = true;
    // This whole session is a symptom check-in on the locked meal.
    _symptomCheckIn = true;
    _wakeWordMicReleased = false; // new session — wake-word mic is armed again

    const question =
        'How are you feeling after your last meal? Let me know about any discomfort — you can rate it 1–10, or just say you\'re feeling good.';
    state = VoiceState(
      status: VoiceStatus.awaitingFollowUp,
      response: question,
      pendingMealId: mealId,
      micPhase: MicPhase.preparing,
      history: const [
        {'role': 'assistant', 'content': question}
      ],
    );

    // Wait a beat so the user can orient before the mic opens — otherwise
    // Android times out on the orientation silence and the restart loop
    // plays a storm of beeps.
    _followUpStartTimer?.cancel();
    _followUpStartTimer = Timer(_followUpStartDelay, () {
      if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
        _beginStt(isFollowUp: true);
      }
    });
  }

  Future<void> _beginStt({bool isFollowUp = false}) async {
    _inFollowUpListen = isFollowUp;
    if (!await _ensureSttInitialized()) {
      return;
    }
    if (isFollowUp && _followUpRestarts == 0) {
      // Let this first session's beep play, then mute the candidate streams so
      // the restart sessions' beeps are silenced. Released on any exit.
      _beepSuppressTimer?.cancel();
      _beepSuppressTimer = Timer(_beepSuppressDelay, () {
        if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
          _beep.suppress();
          _beepSuppressed = true;
        }
      });
    }
    final mode = isFollowUp && _useDictation
        ? ListenMode.dictation
        : ListenMode.confirmation;
    // Hand the mic off from the wake-word service before listening, or
    // SpeechRecognizer is starved (see _releaseWakeWordMic). Swallow failures:
    // if wake word is disabled the service isn't running and the channel throws.
    try {
      await _releaseWakeWordMic();
    } catch (_) {/* wake word off / service not running */}
    // Only wait for the audio HAL to free the input on the first listen of a
    // session; on restarts the mic is already ours, so re-acquire immediately.
    if (!_wakeWordMicReleased) {
      if (_micHandoffDelay > Duration.zero) {
        await Future<void>.delayed(_micHandoffDelay);
      }
      _wakeWordMicReleased = true;
    }
    if (!mounted) return;
    // Flip the UI to "listening" only now that STT is actually about to capture —
    // showing the waveform during the handoff above loses the user's first words.
    if (isFollowUp) {
      state = state.copyWith(micPhase: MicPhase.listening);
    }
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
          if (_inFollowUpListen &&
              state.transcript.isNotEmpty &&
              _followUpRestarts < _maxFollowUpRestarts) {
            // Android fired finalResult early — save what we have and restart.
            _followUpAccumulated = state.transcript;
            _followUpRestarts++;
            _inFollowUpListen = false;
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
                _beginStt(isFollowUp: true);
              }
            });
          } else if (_inFollowUpListen && state.transcript.isEmpty) {
            // finalResult with nothing captured — go idle (tap-to-talk).
            _pauseFollowUpMic();
          } else {
            setThinking();
          }
        }
      },
      onSoundLevelChange: (level) =>
          soundLevel.value = normalizeSoundLevel(level),
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
    _releaseBeepSuppression();
    _inFollowUpListen = false;
    _followUpRestarts = 0;
    _followUpAccumulated = '';
    _useDictation = true;
    if (_stt.isListening) _stt.stop();
    soundLevel.value = 0.0;
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
    await _ready;
    await _tts.speak(prepareForSpeech(response));
  }

  void _stopTts() {
    _ready.then((_) { _tts.stop(); });
  }

  /// Normalizes text for natural TTS. Exposed for unit testing.
  @visibleForTesting
  static String prepareForSpeech(String text) {
    text = _stripEmojis(text);
    // "4/10" → "4 out of 10" so TTS doesn't read it as a fraction
    text = text.replaceAllMapped(
      RegExp(r'(\d+)/(\d+)'),
      (m) => '${m[1]} out of ${m[2]}',
    );
    // "1-10" / "1–10" / "1—10" → "1 to 10" (a range, not a fraction) so TTS
    // doesn't read the dash literally ("one ten").
    text = text.replaceAllMapped(
      RegExp(r'(\d+)\s*[-–—]\s*(\d+)'),
      (m) => '${m[1]} to ${m[2]}',
    );
    return text;
  }

  /// True when Hearty's reply is itself a question (keeps the conversation open
  /// for one more turn). Exposed for unit testing.
  @visibleForTesting
  static bool replyIsQuestion(String reply) => reply.trimRight().endsWith('?');

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
    _stopTts();
    soundLevel.value = 0.0;
    state = const VoiceState();
  }

  void setAwaitingFollowUp() {
    if (!mounted) return;
    // Re-entry guard: arming a follow-up should happen once per turn. If we're
    // already in a follow-up turn, ignore duplicate TTS-completion callbacks so
    // they can't re-arm the mic in a loop (defense-in-depth behind the
    // edge-detected completion in NeuralTtsEngine).
    if (state.status == VoiceStatus.awaitingFollowUp) return;
    final updatedHistory = [
      ...state.history,
      if (state.transcript.isNotEmpty) {'role': 'user', 'content': state.transcript},
      if (state.response.isNotEmpty) {'role': 'assistant', 'content': state.response},
    ];
    state = state.copyWith(
      status: VoiceStatus.awaitingFollowUp,
      history: updatedHistory,
      transcript: '',
      micPhase: MicPhase.preparing,
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
    if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
      await _beginStt(isFollowUp: true);
    }
  }

  void dismiss() {
    _releaseBeepSuppression();
    _followUpStartTimer?.cancel();
    if (_stt.isListening) _stt.stop();
    _stopTts();
    soundLevel.value = 0.0;
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
      final reply =
          result.reply.isNotEmpty ? result.reply : 'Got it! How are you feeling?';
      setResponse(
        reply,
        askFollowUp: replyIsQuestion(reply),
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
        symptomFollowUp: _symptomCheckIn,
      );
      if (!mounted) return;
      final reply = result.reply.isNotEmpty ? result.reply : 'Got it, thanks!';
      final keepGoing = replyIsQuestion(reply);
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
    _releaseBeepSuppression();
    _followUpStartTimer?.cancel();
    soundLevel.dispose();
    _stt.stop();
    _ready.then((_) => _tts.dispose());
    super.dispose();
  }
}
