import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/offline_exception.dart';
import '../../../core/api/providers/last_logged_provider.dart';
import '../../../core/api/providers/meals_provider.dart' show syncTriggerProvider;
import '../../../core/api/providers/preferences_provider.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/audio/audio_beep_channel.dart';
import '../../../core/offline/local_voice_queue_dao.dart';
import '../../../core/stt/stt_engine.dart';
import '../../../core/stt/on_device_stt_engine.dart';
import '../../../core/tts/tts_engine.dart';
import '../../../core/tts/tts_engine_factory.dart';
import '../../wake_word/wake_word_channel.dart';
import '../models/voice_state.dart';

const _uuid = Uuid();

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  return VoiceNotifier(ref: ref);
});

/// Drives the voice lifecycle on top of an [SttEngine] (on-device sherpa
/// streaming by default; injectable for tests). The engine streams partials and
/// signals turn-end via its own trailing-silence policy ([SttEngine.start]'s
/// `onAutoSubmit`); we own only the state machine: listening → submit → thinking
/// → responding → awaitingFollowUp, with one ding per session, half-duplex TTS
/// gating (the engine is only ever opened after TTS completion — see the call
/// sites of [_openSession]), and the wake-word mic handoff.
class VoiceNotifier extends StateNotifier<VoiceState> {
  VoiceNotifier({
    Ref? ref,
    TtsEngine? ttsForTesting,
    SttEngine Function()? engineFactory,
    Duration? followUpStartDelay,
    AudioBeepChannel? beepChannelForTesting,
    Future<void> Function()? releaseWakeWordMic,
    Duration? micHandoffDelay,
    bool autoSubmit = true,
    double autoSubmitSilenceSeconds = 2.5,
  })  : _ref = ref,
        _injectedTts = ttsForTesting,
        _engineFactory = engineFactory ??
            (() => OnDeviceSttEngine(silenceSeconds: autoSubmitSilenceSeconds)),
        _autoSubmit = autoSubmit,
        _followUpStartDelay =
            followUpStartDelay ?? const Duration(milliseconds: 2500),
        _beep = beepChannelForTesting ?? AudioBeepChannel(),
        _releaseWakeWordMic =
            releaseWakeWordMic ?? WakeWordChannel.stopListening,
        _micHandoffDelay =
            micHandoffDelay ?? const Duration(milliseconds: 250),
        super(const VoiceState()) {
    _ready = _initTts();
  }

  final Ref? _ref;
  final TtsEngine? _injectedTts;
  late TtsEngine _tts;
  late final Future<void> _ready;
  bool _askFollowUp = true;

  // STT engine — created per capture session via the factory, torn down on every
  // exit path. _partialSub forwards live partials into the transcript.
  final SttEngine Function() _engineFactory;
  final bool _autoSubmit;
  SttEngine? _engine;
  StreamSubscription<String>? _partialSub;

  // True while in the post-meal symptom check-in (started by the nudge). Tells
  // the backend this turn is a "how are you feeling?" response about an
  // already-logged meal so it never edits the meal (see symptom_followup).
  bool _symptomCheckIn = false;

  // Orientation delay before the follow-up mic opens, so the user can read the
  // question first. Cancelable via dismiss(); injectable for tests.
  final Duration _followUpStartDelay;
  Timer? _followUpStartTimer;

  // One short "I'm listening" tone per capture session (sherpa on-device has no
  // system start beep of its own, unlike the old SpeechRecognizer).
  final AudioBeepChannel _beep;

  // The always-on wake-word foreground service holds the microphone (an
  // AudioRecord on VOICE_RECOGNITION). On Android the existing capture client
  // wins, so a new mic stream is starved unless we hand the mic off first —
  // exactly what the native onWakeWordDetected() does for the wake-word path. We
  // mirror that for every capture session and re-arm the service when the voice
  // overlay closes (VoiceOverlayScreen.dispose). _micHandoffDelay gives the
  // audio HAL a beat to release the input before we grab it. Injectable so unit
  // tests stay synchronous and timer-free.
  final Future<void> Function() _releaseWakeWordMic;
  final Duration _micHandoffDelay;
  bool _wakeWordMicReleased = false;

  // Live mic amplitude (0..1) for the prism visualiser. The on-device engine
  // does not yet surface RMS, so this stays at 0 for now (flat beam) — wiring an
  // amplitude stream off the engine is a follow-up. Kept so the overlay and the
  // pure normalize helper keep compiling/working.
  final ValueNotifier<double> soundLevel = ValueNotifier<double>(0.0);

  /// Maps a recognizer's rms-dB-ish sound level (~-2 silence .. ~10 loud) to a
  /// 0..1 amplitude for the visualiser.
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

  // ---------------------------------------------------------------------------
  // Capture session lifecycle
  // ---------------------------------------------------------------------------

  /// Opens a single capture session. CRITICAL: every caller of this is reached
  /// only after any TTS has completed (startListening = no TTS; setAwaitingFollowUp
  /// = TTS-completion handler; primeForSymptomFollowUp/resumeFollowUpListening =
  /// no TTS), which is what keeps the lifecycle half-duplex. Do not call it from
  /// a path that can run while Hearty is speaking.
  Future<void> _openSession({required bool isFollowUp}) async {
    await _closeEngine();
    _wakeWordMicReleased = false;
    // Preserve the listening vs awaitingFollowUp distinction: the overlay routes
    // the submit on the pre-thinking status (awaitingFollowUp → sendFollowUpToApi
    // with history/mealId/symptom_followup; else → sendToChat). Blanketing this
    // to listening would drop follow-up context.
    state = state.copyWith(
      status: isFollowUp ? VoiceStatus.awaitingFollowUp : VoiceStatus.listening,
      micPhase: MicPhase.preparing,
      transcript: '',
    );

    // Hand the mic off from the wake-word service first, or the new capture
    // stream is starved. Swallow failures: if wake word is off the service
    // isn't running and the channel throws.
    try {
      await _releaseWakeWordMic();
    } catch (_) {/* wake word off / service not running */}
    if (!_wakeWordMicReleased) {
      if (_micHandoffDelay > Duration.zero) {
        await Future<void>.delayed(_micHandoffDelay);
      }
      _wakeWordMicReleased = true;
    }
    // The user may have dismissed (→ idle) or submitted during the handoff.
    if (!mounted ||
        (state.status != VoiceStatus.listening &&
            state.status != VoiceStatus.awaitingFollowUp)) {
      return;
    }

    final engine = _engineFactory();
    _engine = engine;
    _partialSub = engine.partials.listen((text) {
      // Ignore stray partials that land after we've left listening.
      if (state.status == VoiceStatus.listening ||
          state.status == VoiceStatus.awaitingFollowUp) {
        setTranscript(text);
      }
    });

    try {
      await engine.start(onAutoSubmit: _autoSubmit ? _onAutoSubmit : null);
      if (!mounted) return;
      _beep.ding(); // exactly one ding, once capture is actually live
      state = state.copyWith(micPhase: MicPhase.listening);
    } catch (_) {
      // Model missing, mic denied, etc. — drop to manual (tap-to-talk + text).
      await _closeEngine();
      _pauseForManual();
    }
  }

  // Bridges the engine's `void Function()?` auto-submit callback to async submit.
  void _onAutoSubmit() {
    submit();
  }

  /// Stop capturing, ship the (final) transcript, and advance to thinking. Wired
  /// to the engine's auto-submit and to the overlay's manual Submit. Safe to call
  /// when no engine is open (text-entry path) — it just advances.
  Future<void> submit() async {
    final engine = _engine;
    if (engine == null) {
      setThinking();
      return;
    }
    final result = await engine.stop();
    await _closeEngine();
    if (!mounted) return;
    final text = result.transcript.trim();
    if (text.isNotEmpty) setTranscript(text);
    setThinking();
  }

  void _pauseForManual() {
    soundLevel.value = 0.0;
    if (mounted) state = state.copyWith(micPhase: MicPhase.paused);
  }

  Future<void> _closeEngine() async {
    final sub = _partialSub;
    _partialSub = null;
    final e = _engine;
    _engine = null;
    await sub?.cancel();
    await e?.dispose();
  }

  /// Re-opens one follow-up capture session — wired to the overlay's
  /// "Tap to talk" button after the mic dropped to manual.
  void resumeFollowUpListening() {
    if (state.micPhase != MicPhase.paused) return;
    _openSession(isFollowUp: true);
  }

  void startListening() {
    // A fresh manual/wake-word session is a normal meal log, not a check-in.
    _symptomCheckIn = false;
    state = const VoiceState(status: VoiceStatus.listening);
    _openSession(isFollowUp: false);
  }

  /// Opens the overlay in follow-up mode with Hearty's symptom question already
  /// showing, mic active after an orientation beat, no TTS. [mealId] links the
  /// response to the meal that triggered the nudge notification.
  void primeForSymptomFollowUp({String? mealId}) {
    _stopTts();
    // This whole session is a symptom check-in on the locked meal.
    _symptomCheckIn = true;

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

    // Wait a beat so the user can orient before the mic opens.
    _followUpStartTimer?.cancel();
    _followUpStartTimer = Timer(_followUpStartDelay, () {
      if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
        _openSession(isFollowUp: true);
      }
    });
  }

  void setTranscript(String text) {
    state = state.copyWith(transcript: text);
  }

  void setThinking() {
    _followUpStartTimer?.cancel();
    unawaited(_closeEngine());
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
    _ready.then((_) {
      _tts.stop();
    });
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
    // they can't re-open the mic in a loop (defense-in-depth behind the
    // edge-detected completion in NeuralTtsEngine).
    if (state.status == VoiceStatus.awaitingFollowUp) return;
    final updatedHistory = [
      ...state.history,
      if (state.transcript.isNotEmpty)
        {'role': 'user', 'content': state.transcript},
      if (state.response.isNotEmpty)
        {'role': 'assistant', 'content': state.response},
    ];
    state = state.copyWith(
      status: VoiceStatus.awaitingFollowUp,
      history: updatedHistory,
      transcript: '',
      micPhase: MicPhase.preparing,
    );
    _openSession(isFollowUp: true);
  }

  void dismiss() {
    _followUpStartTimer?.cancel();
    unawaited(_closeEngine());
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
      setResponse(
          "That's outside what I track. I focus on food, symptoms, and wellbeing.",
          askFollowUp: false);
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
      final reply = result.reply.isNotEmpty
          ? result.reply
          : 'Got it! How are you feeling?';
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
          await NotificationService.scheduleFollowUpNotification(
              prefs.nudgeDelayMinutes);
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
        conversationStyle:
            ref.read(preferencesProvider).valueOrNull?.conversationStyle ??
                'warm',
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
    _followUpStartTimer?.cancel();
    unawaited(_closeEngine());
    soundLevel.dispose();
    _ready.then((_) => _tts.dispose());
    super.dispose();
  }
}
