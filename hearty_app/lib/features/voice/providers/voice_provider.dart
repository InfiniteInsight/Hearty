import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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
import '../../../core/stt/cloud_stt_engine.dart';
import '../../../core/stt/on_device_batch_stt_engine.dart';
import '../../../core/stt/on_device_model.dart';
import '../../../core/stt/asr_model_manager.dart';
import '../../../core/stt/stt_engine_selector.dart';
import '../../../core/tts/tts_engine.dart';
import '../../../core/tts/tts_engine_factory.dart';
import '../../wake_word/wake_word_channel.dart';
import '../models/voice_state.dart';

const _uuid = Uuid();

/// App-wide ASR model manager: owns the 275 MB+ warm recognizer isolate and any
/// in-flight model download. keepAlive (NOT autoDispose) so popping the Settings
/// screen never tears down an active Parakeet download or the warm isolate — the
/// manager self-releases via its own 3-min idle timer. Shared by [voiceProvider]
/// (hot path) and the dictation Settings screen (model switch / pre-warm).
final asrModelManagerProvider = Provider<AsrModelManager>((ref) {
  final mgr = AsrModelManager();
  ref.onDispose(mgr.dispose);
  return mgr;
});

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  return VoiceNotifier(
      ref: ref, modelManager: ref.read(asrModelManagerProvider));
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
    bool useCloudWhenOnline = false, // dormant by default — on-device is the path
    OnDeviceModel onDeviceModel = OnDeviceModel.defaultModel,
    AsrModelManager? modelManager,
    Future<bool> Function()? isOnline,
  })  : _ref = ref,
        _injectedTts = ttsForTesting,
        // Null in production → _openSession selects the engine per prefs +
        // connectivity. Tests inject a synchronous factory to bypass selection.
        _engineFactory = engineFactory,
        _autoSubmit = autoSubmit,
        _silenceSeconds = autoSubmitSilenceSeconds,
        _useCloudWhenOnline = useCloudWhenOnline,
        _onDeviceModelFallback = onDeviceModel,
        _modelManager = modelManager ?? AsrModelManager(),
        _isOnline = isOnline ?? _defaultIsOnline,
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

  // STT engine — created per capture session, torn down on every exit path.
  // _partialSub forwards live partials into the transcript. In production
  // _engineFactory is null and _selectEngine() picks cloud vs on-device per
  // connectivity + _useCloudWhenOnline; tests inject a synchronous factory.
  final SttEngine Function()? _engineFactory;
  final bool _autoSubmit;
  final double _silenceSeconds;
  final bool _useCloudWhenOnline; // fallback when prefs unavailable (tests)
  final OnDeviceModel _onDeviceModelFallback; // ditto
  final AsrModelManager _modelManager;
  final Future<bool> Function() _isOnline;
  SttEngine? _engine;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<double>? _amplitudeSub;

  static Future<bool> _defaultIsOnline() async {
    final r = await Connectivity().checkConnectivity();
    return r.any((x) => x != ConnectivityResult.none);
  }

  /// Production engine selection (bypassed when a test [engineFactory] is set):
  /// cloud only if the user re-enabled it AND online (dormant by default); else
  /// the on-device batch engine for the selected model. CRITICAL: never block on
  /// a download here — if the model isn't warm yet, kick off the fetch+warm
  /// out-of-band and throw [SttNotReadyException] so the capture path drops to
  /// text entry instead of hanging.
  Future<SttEngine> _selectEngine() async {
    final prefs = _ref?.read(preferencesProvider).valueOrNull;
    final useCloud = prefs?.useCloudWhenOnline ?? _useCloudWhenOnline;
    final silenceSeconds = prefs?.autoSubmitSilenceSeconds ?? _silenceSeconds;
    if (SttEngineSelector.useCloud(
        online: await _isOnline(), useCloudWhenOnline: useCloud)) {
      return CloudSttEngine(
        silenceSeconds: silenceSeconds,
        transcribe: (pcm, sr) => _ref!
            .read(heartyApiClientProvider)
            .transcribe(pcm: pcm, sampleRate: sr),
      );
    }
    final model = prefs != null
        ? OnDeviceModel.fromPrefString(prefs.useOnDeviceModel)
        : _onDeviceModelFallback;
    final warm = _modelManager.warmDecodeOrNull(model);
    if (warm != null) {
      return OnDeviceBatchSttEngine(silenceSeconds: silenceSeconds, decode: warm);
    }
    // Not warm. If the model is already downloaded — the warm isolate just
    // self-released after its 3-min idle timeout (a deliberate RAM choice), or
    // is still warming from the launch preload — warm it now and WAIT. The
    // overlay shows "getting ready", then listens, instead of silently dropping
    // to manual and forcing a second tap (that was this bug). An on-disk model
    // warms in seconds; the timeout is only a safety net against a hung isolate.
    if (await _modelManager.isReady(model)) {
      try {
        await _modelManager
            .ensureAndWarm(model)
            .timeout(const Duration(seconds: 20));
        final warmed = _modelManager.warmDecodeOrNull(model);
        if (warmed != null) {
          return OnDeviceBatchSttEngine(
              silenceSeconds: silenceSeconds, decode: warmed);
        }
      } catch (_) {/* warm failed/timed out → manual */}
      throw const SttNotReadyException();
    }
    // Not downloaded — a multi-minute fetch. Don't block the capture path: warm
    // in the background (swallow bg errors) and fall back to manual this turn.
    unawaited(_modelManager.ensureAndWarm(model).catchError((_) {}));
    throw const SttNotReadyException();
  }

  /// Auto-submit (trailing-silence turn end) honors the user's pref; the
  /// constructor value is the test/no-prefs fallback. Wired here so the Settings
  /// toggle actually gates `onAutoSubmit` instead of being dead UI.
  bool get _effectiveAutoSubmit =>
      _ref?.read(preferencesProvider).valueOrNull?.autoSubmit ?? _autoSubmit;

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

  // Live mic amplitude (raw linear RMS, ~0 silence) for the prism visualiser,
  // fed from the active engine's amplitude stream in _openSession and reset to 0
  // in _closeEngine. The prism shader (PrismShaderState) owns the noise gate +
  // smoothing, so the raw RMS flows through untouched. Read each frame by
  // PrismWaveform via this ValueNotifier.
  final ValueNotifier<double> soundLevel = ValueNotifier<double>(0.0);

  Future<void> _initTts() async {
    _tts = _injectedTts ?? await createTtsEngine();
    _tts.setCompletionHandler(() {
      if (!mounted) return;
      // Only advance when TTS finished on its OWN while we were still speaking
      // the response. dismiss()/stopSpeaking() also stop TTS, which fires this
      // same callback — without this guard, cancelling mid-response would
      // resurrect the turn and open a ghost capture session that fights the
      // wake-word mic (user taps X "between turns" → wake word goes deaf).
      if (state.status != VoiceStatus.responding) return;
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

  // Guards against two capture sessions opening at once. Matters now that a
  // cold-model open awaits the warm (~seconds): a second mic tap / follow-up
  // timer firing mid-warm would otherwise run a second _openSession, adopt a
  // second engine, and leak the first (mic held). One session opens at a time.
  bool _opening = false;

  /// Opens a single capture session. CRITICAL: every caller of this is reached
  /// only after any TTS has completed (startListening = no TTS; setAwaitingFollowUp
  /// = TTS-completion handler; primeForSymptomFollowUp/resumeFollowUpListening =
  /// no TTS), which is what keeps the lifecycle half-duplex. Do not call it from
  /// a path that can run while Hearty is speaking.
  Future<void> _openSession({required bool isFollowUp}) async {
    if (_opening) return;
    _opening = true;
    try {
      await _openSessionImpl(isFollowUp: isFollowUp);
    } finally {
      _opening = false;
    }
  }

  Future<void> _openSessionImpl({required bool isFollowUp}) async {
    await _closeEngine();
    // _closeEngine awaits; the notifier may have been disposed in the meantime
    // (caller fired this without awaiting). Bail before touching state.
    if (!mounted) return;
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

    // Production selection (connectivity + model readiness) vs injected test
    // factory. A not-ready model / selection failure drops to manual (text
    // entry) rather than hanging — never block the capture path on a download.
    final SttEngine engine;
    try {
      engine = _engineFactory != null ? _engineFactory() : await _selectEngine();
    } catch (_) {
      if (mounted) _pauseForManual();
      return;
    }
    // _selectEngine adds another await; the user may have dismissed during the
    // connectivity check, so re-check before adopting the engine.
    if (!mounted ||
        (state.status != VoiceStatus.listening &&
            state.status != VoiceStatus.awaitingFollowUp)) {
      await engine.dispose();
      return;
    }
    _engine = engine;
    _partialSub = engine.partials.listen((text) {
      // Ignore stray partials that land after we've left listening.
      if (state.status == VoiceStatus.listening ||
          state.status == VoiceStatus.awaitingFollowUp) {
        setTranscript(text);
      }
    });
    // Drive the prism visualiser from the engine's live mic RMS. The value is
    // raw linear RMS; PrismShaderState owns the noise gate + smoothing, so it
    // flows through untouched.
    _amplitudeSub = engine.amplitude.listen((rms) {
      if (state.status == VoiceStatus.listening ||
          state.status == VoiceStatus.awaitingFollowUp) {
        soundLevel.value = rms;
      }
    });

    try {
      await engine.start(
          onAutoSubmit: _effectiveAutoSubmit ? _onAutoSubmit : null);
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
    // engine.stop() can take up to ~2s on device; the user may have dismissed
    // (→ idle) during that window. dismiss() does not unmount the app-scoped
    // notifier, so re-check the status before forcing the turn forward — else we
    // resurrect a cancelled turn into thinking. (Restores the old
    // _autoSubmitIfPending guard the speech_to_text path had.)
    if (state.status != VoiceStatus.listening &&
        state.status != VoiceStatus.awaitingFollowUp) {
      return;
    }
    final text = result.transcript.trim();
    if (!result.ok || text.isEmpty) {
      // Failed transcription (e.g. cloud network error despite connectivity
      // reporting online), OR nothing intelligible. Cloud returns '' on
      // silence/noise and has no partials, so advancing would pin a dead
      // 'thinking' spinner (sendToChat/sendFollowUpToApi early-return on empty).
      // Drop to manual — re-record or type — instead. Captured audio is lost
      // (stated Plan C v1 limit).
      _pauseForManual();
      return;
    }
    setTranscript(text);
    setThinking();
  }

  void _pauseForManual() {
    soundLevel.value = 0.0;
    if (mounted) state = state.copyWith(micPhase: MicPhase.paused);
  }

  Future<void> _closeEngine() async {
    final sub = _partialSub;
    _partialSub = null;
    final ampSub = _amplitudeSub;
    _amplitudeSub = null;
    final e = _engine;
    _engine = null;
    // Drop the prism back to a calm beam once capture ends. Done synchronously
    // before any await: dispose() calls this unawaited and then synchronously
    // disposes soundLevel, so a post-await write would hit a disposed notifier.
    if (mounted) soundLevel.value = 0.0;
    await sub?.cancel();
    await ampSub?.cancel();
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
    // Tear down any lingering engine from a previous session now, rather than
    // waiting for the orientation timer to fire _openSession ~2.5s later.
    unawaited(_closeEngine());
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
