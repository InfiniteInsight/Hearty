# Voice Rebuild — Phase C: Cloud Engine + Online/Offline Selection Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the cloud transcription path and the online/offline engine selection from the hybrid design. When online (and the setting allows it), capture audio on-device and transcribe it via the Hearty backend → Google Cloud Speech-to-Text (best accuracy on open food/brand vocab). When offline, keep using the Phase-B on-device sherpa engine. Both paths share the same `SttEngine` lifecycle, the same trailing-silence auto-submit, and the same mic handoff.

**Architecture:** A new `CloudSttEngine implements SttEngine` owns a `record` PCM16 mic stream, buffers the audio in memory (capped at 60 s — see below), and on `stop()` POSTs it to `POST /api/transcribe`; `partials` is empty (cloud is batch). A pure `SttEngineSelector` decides cloud-vs-on-device from `(online, useCloudWhenOnline)`. `VoiceNotifier` grows an async `_selectEngine()` (used only when no test `engineFactory` is injected) that runs the connectivity check and builds the chosen engine — `CloudSttEngine` gets a `transcribe` callback closing over `HeartyApiClient`. The backend adds `POST /api/transcribe`, a thin JWT-guarded proxy to Google STT v1 `speech:recognize` (sync REST + API key via `httpx`).

**Tech Stack:** Flutter/Dart (`record`, `dio`, `connectivity_plus` — all already deps), FastAPI + `httpx` (already a dep), Google Cloud Speech-to-Text v1 `speech:recognize`.

**Spec:** `docs/superpowers/specs/2026-06-07-voice-lifecycle-rebuild-design.md` (this is **P2**). Prereqs: Phase A + Phase B merged (`SttEngine`, `OnDeviceSttEngine`, `SilenceDetector`, the `VoiceNotifier` lifecycle). Follow-on: Plan D (Flow 3 reliability, **the persisted `useCloudWhenOnline` setting + UI**, model download, remove `speech_to_text`).

**Two design decisions settled before writing (they shape the engine/factory):**
1. **Google sync `speech:recognize` caps inline audio at ~60 s / ~10 MB.** Auto-submit at 2.5 s trailing silence means real utterances are almost always < 30 s, but the spec's ~2-min safety cap could exceed Google's limit. Resolution (no `longrunningrecognize` in C): **`CloudSttEngine` caps its PCM buffer at 60 s; reaching the cap fires `onAutoSubmit`** to flush what's buffered. At 60 s: ~1.9 MB raw PCM → ~2.6 MB base64, comfortably under Google's 10 MB inline ceiling.
2. **The engine factory must reach `HeartyApiClient`.** `VoiceNotifier`'s injectable `engineFactory` stays `SttEngine Function()?` (synchronous — the test seam is untouched). In production it is left null, and `_openSession` calls an async `_selectEngine()` that does the connectivity check and constructs the engine, passing `CloudSttEngine` a `transcribe` callback that closes over `_ref.read(heartyApiClientProvider)`. `record` is the untestable-native part; the `transcribe` callback is the test seam (mirrors how `OnDeviceSttEngine` split native vs logic).

**Scope guards for Phase C:**
- **Selection reads a `useCloudWhenOnline` bool that defaults `true`.** The **persisted user setting + the Settings toggle are Plan D** (they need a preferences/DB change and the settings UI, which Plan D owns). Phase C plumbs the bool as a `VoiceNotifier` constructor param so Plan D can wire it to the pref with one line.
- **Mid-session cloud failure → manual/text re-entry; the captured audio is lost.** This is a stated v1 limitation, not a soft "maybe." The offline voice queue (`local_voice_queue_dao`) stores **transcripts, not audio**, so queuing raw audio for later transcription is new work, deferred. On-device **re-decode of the buffered audio** is the real fix and is also deferred (Plan D / follow-up). Note: `connectivity_plus` reporting "online" does **not** guarantee the backend is reachable (captive portal, backend down), which is exactly why this runtime fallback must exist even when selection chose cloud.
- **No new lifecycle states.** Cloud transcription happens inside `stop()`/`submit()`; during the network call the overlay shows the existing "listening" visual, then "thinking". A dedicated **"Transcribing…" micro-state is deferred to Plan D** polish. (The Phase-B `submit()` status-guard already protects a user dismissing during the multi-second cloud `stop()`.)
- **Data-logging-off is a GCP project setting**, not a request parameter — a deployment note, not code.

---

## File structure

| File | Responsibility |
|---|---|
| `hearty-api/app/routers/transcribe.py` | `POST /api/transcribe` — JWT-guarded proxy to Google STT |
| `hearty-api/app/main.py` | register the new router |
| `hearty-api/tests/test_transcribe.py` | unit tests (mock `httpx`, auth override, error JSON) |
| `hearty_app/lib/core/api/hearty_api_client.dart` | add `transcribe()` (own 60 s timeout) |
| `hearty_app/lib/core/stt/cloud_stt_engine.dart` | `CloudSttEngine` — mic + 60 s PCM buffer + silence detector → POST |
| `hearty_app/lib/core/stt/stt_engine_selector.dart` | pure `SttEngineSelector.useCloud(online, useCloudWhenOnline)` |
| `hearty_app/lib/features/voice/providers/voice_provider.dart` | async `_selectEngine()` + connectivity + `useCloudWhenOnline` param |
| `hearty_app/test/core/stt/stt_engine_selector_test.dart` | selection truth table |
| `hearty_app/test/core/stt/cloud_stt_engine_test.dart` | buffer → transcribe → result (fake transcribe + injected recorder) |
| `hearty_app/test/features/voice/voice_provider_test.dart` | extend: cloud engine via injected factory still drives the lifecycle |

---

## C0 — Backend `POST /api/transcribe`

Goal: a thin, well-tested proxy. The Flutter client never holds the Google key.

### Task C0.1: The transcribe router

**Files:**
- Create: `hearty-api/app/routers/transcribe.py`
- Modify: `hearty-api/app/main.py`

- [ ] **Step 1: Write the router**

```python
import base64
import logging
import os

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.auth import get_current_user

logger = logging.getLogger(__name__)

router = APIRouter()

# Google Cloud Speech-to-Text v1 synchronous recognize. The API key is
# server-side only; the Flutter client authenticates to *us* with its JWT.
# NOTE (deployment): disable data-logging at the GCP project level so audio is
# transient-in-transit only — there is no per-request flag for it.
_GOOGLE_STT_URL = "https://speech.googleapis.com/v1/speech:recognize"
_API_KEY = os.getenv("GOOGLE_STT_API_KEY", "")
_LANGUAGE = os.getenv("GOOGLE_STT_LANGUAGE", "en-US")
_MODEL = os.getenv("GOOGLE_STT_MODEL", "latest_long")


class TranscribeRequest(BaseModel):
    # base64-encoded headerless LINEAR16 PCM (mono).
    audio: str
    sample_rate: int = 16000


class TranscribeResponse(BaseModel):
    transcript: str


@router.post("/api/transcribe", status_code=200)
async def transcribe(
    body: TranscribeRequest,
    user=Depends(get_current_user),
) -> TranscribeResponse:
    if not _API_KEY:
        logger.error("GOOGLE_STT_API_KEY not configured")
        raise HTTPException(status_code=503, detail="Transcription unavailable")
    if not body.audio:
        return TranscribeResponse(transcript="")

    payload = {
        "config": {
            "encoding": "LINEAR16",
            "sampleRateHertz": body.sample_rate,
            "languageCode": _LANGUAGE,
            "model": _MODEL,
            "enableAutomaticPunctuation": True,
        },
        "audio": {"content": body.audio},
    }
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                _GOOGLE_STT_URL, params={"key": _API_KEY}, json=payload
            )
            resp.raise_for_status()
            data = resp.json()
    except httpx.HTTPError as e:
        logger.error("Google STT request failed: %s", e)
        raise HTTPException(status_code=502, detail="Transcription failed")

    # results[].alternatives[0].transcript — concatenate result segments.
    transcript = " ".join(
        r["alternatives"][0]["transcript"].strip()
        for r in data.get("results", [])
        if r.get("alternatives")
    ).strip()
    return TranscribeResponse(transcript=transcript)
```

In `app/main.py`, mirror the other routers:

```python
from app.routers import transcribe   # with the other router imports
app.include_router(transcribe.router)  # with the other include_router calls
```

- [ ] **Step 2: Decode-sanity** (no code change) — confirm the client will send headerless LINEAR16 PCM base64 (C1 does exactly this); Google wants raw PCM in `audio.content` with `encoding=LINEAR16` + `sampleRateHertz`, **no WAV header**.

### Task C0.2: Tests (mock Google, no network)

**Files:**
- Create: `hearty-api/tests/test_transcribe.py`

- [ ] **Step 1: Write the tests** (follow `test_chat_followup_unit.py`: `TestClient`, `app.dependency_overrides[get_current_user]`, `monkeypatch` the `httpx` call)

```python
"""Unit tests for /api/transcribe — no network, no real JWT.

Mocks the outbound Google STT httpx call so transcript parsing, auth, the
missing-key guard, and upstream-error mapping are tested deterministically.
"""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import transcribe as t


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(t, "_API_KEY", "test-key")
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1"}
    yield TestClient(app)
    app.dependency_overrides.clear()


class _FakeResp:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


def _patch_google(monkeypatch, payload):
    class _FakeAsyncClient:
        def __init__(self, *a, **k):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def post(self, *a, **k):
            return _FakeResp(payload)

    monkeypatch.setattr(t.httpx, "AsyncClient", _FakeAsyncClient)


def test_returns_transcript(client, monkeypatch):
    _patch_google(monkeypatch, {
        "results": [{"alternatives": [{"transcript": "I had an IQ bar"}]}]
    })
    r = client.post("/api/transcribe", json={"audio": "QUJD", "sample_rate": 16000})
    assert r.status_code == 200
    assert r.json()["transcript"] == "I had an IQ bar"


def test_concatenates_multiple_results(client, monkeypatch):
    _patch_google(monkeypatch, {"results": [
        {"alternatives": [{"transcript": "I had a turkey sandwich"}]},
        {"alternatives": [{"transcript": "and a coffee"}]},
    ]})
    r = client.post("/api/transcribe", json={"audio": "QUJD"})
    assert r.json()["transcript"] == "I had a turkey sandwich and a coffee"


def test_empty_audio_short_circuits(client):
    r = client.post("/api/transcribe", json={"audio": ""})
    assert r.status_code == 200
    assert r.json()["transcript"] == ""


def test_missing_key_returns_503(client, monkeypatch):
    monkeypatch.setattr(t, "_API_KEY", "")
    r = client.post("/api/transcribe", json={"audio": "QUJD"})
    assert r.status_code == 503


def test_upstream_error_maps_to_502(client, monkeypatch):
    class _BoomClient:
        def __init__(self, *a, **k):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def post(self, *a, **k):
            raise t.httpx.ConnectError("boom")

    monkeypatch.setattr(t.httpx, "AsyncClient", _BoomClient)
    r = client.post("/api/transcribe", json={"audio": "QUJD"})
    assert r.status_code == 502


def test_requires_auth():
    # No dependency override → real get_current_user rejects.
    c = TestClient(app)
    r = c.post("/api/transcribe", json={"audio": "QUJD"})
    assert r.status_code in (401, 403)
```

- [ ] **Step 2: Run** — `cd hearty-api && (set -a; . ../.env 2>/dev/null; set +a) ; python -m pytest tests/test_transcribe.py -q`
  (Source repo-root `.env` for the Supabase vars `chat.py`'s module-level `create_client` needs at import; the chat tests already rely on this.)
  Expected: 6 passed.

- [ ] **Step 3: Commit**

```bash
git add hearty-api/app/routers/transcribe.py hearty-api/app/main.py hearty-api/tests/test_transcribe.py
git commit -m "feat(api): POST /api/transcribe — JWT-guarded Google STT proxy

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## C1 — Client transcribe call + `CloudSttEngine`

### Task C1.1: `HeartyApiClient.transcribe()`

**Files:**
- Modify: `hearty_app/lib/core/api/hearty_api_client.dart`

- [ ] **Step 1: Add the method** (own timeout — the shared `receiveTimeout` is 30 s, but a 2.6 MB upload + Google processing wants more headroom)

```dart
import 'dart:convert'; // base64Encode — add to the imports
import 'dart:typed_data';

  /// Transcribes headerless LINEAR16 PCM [pcm] (mono, [sampleRate] Hz) via the
  /// backend Google STT proxy. Returns the transcript ('' if nothing heard).
  /// Throws (incl. [OfflineException]) on failure so the caller can fall back.
  Future<String> transcribe({
    required Uint8List pcm,
    int sampleRate = 16000,
  }) {
    return _call(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/transcribe',
        data: {'audio': base64Encode(pcm), 'sample_rate': sampleRate},
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      return (response.data?['transcript'] as String?)?.trim() ?? '';
    });
  }
```

- [ ] **Step 2: Analyze + commit**

Run: `cd hearty_app && flutter analyze lib/core/api/hearty_api_client.dart`

```bash
git add hearty_app/lib/core/api/hearty_api_client.dart
git commit -m "feat(api-client): transcribe() posts PCM to the STT proxy (60s timeout)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task C1.2: `CloudSttEngine`

**Files:**
- Create: `hearty_app/lib/core/stt/cloud_stt_engine.dart`
- Test: `hearty_app/test/core/stt/cloud_stt_engine_test.dart`

Design: same shape as `OnDeviceSttEngine` (mic + `SilenceDetector` for auto-submit) but instead of an ASR isolate it **buffers PCM** and transcribes on `stop()`. `partials` is an empty broadcast stream (batch — no interim text). The mic + transcribe call are injectable so the buffer/cap/post logic is unit-testable without `record` or the network.

- [ ] **Step 1: Write the failing test** (inject a fake transcribe + drive PCM directly)

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/cloud_stt_engine.dart';

Uint8List _pcmBytes(int samples) => Uint8List(samples * 2); // silence, 16-bit

void main() {
  group('CloudSttEngine', () {
    test('buffers fed PCM and transcribes it on stop', () async {
      Uint8List? sent;
      final engine = CloudSttEngine(
        silenceSeconds: 2.5,
        transcribe: (pcm, sr) async {
          sent = pcm;
          return 'i had a turkey sandwich';
        },
      );
      // ingestForTest mimics the mic callback without `record`.
      engine.ingestForTest(_pcmBytes(1600));
      engine.ingestForTest(_pcmBytes(1600));
      final result = await engine.stop();
      expect(result.ok, isTrue);
      expect(result.transcript, 'i had a turkey sandwich');
      expect(sent!.length, 1600 * 2 * 2); // both chunks buffered
    });

    test('caps the buffer at maxBufferSeconds and fires auto-submit', () async {
      var autoSubmits = 0;
      final engine = CloudSttEngine(
        silenceSeconds: 2.5,
        maxBufferSeconds: 1, // 1s = 16000 samples
        transcribe: (pcm, sr) async => '',
      );
      await engine.start(onAutoSubmit: () => autoSubmits++);
      engine.ingestForTest(_pcmBytes(16000)); // exactly the cap
      engine.ingestForTest(_pcmBytes(1600));  // overflow ignored
      expect(autoSubmits, 1);
      final result = await engine.stop();
      // buffer never exceeds the cap
      expect(result.ok, isTrue);
    });

    test('returns ok:false when transcribe throws (caller falls back)',
        () async {
      final engine = CloudSttEngine(
        silenceSeconds: 2.5,
        transcribe: (pcm, sr) async => throw StateError('network'),
      );
      engine.ingestForTest(_pcmBytes(1600));
      final result = await engine.stop();
      expect(result.ok, isFalse);
      expect(result.transcript, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `cd hearty_app && flutter test test/core/stt/cloud_stt_engine_test.dart` (FAIL — undefined).

- [ ] **Step 3: Implement**

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'silence_detector.dart';
import 'stt_engine.dart';

const _kSampleRate = 16000;

/// Cloud [SttEngine]: owns a `record` PCM16 mic stream, buffers the audio in
/// memory (capped at [maxBufferSeconds] so it stays under Google sync
/// recognize's ~60 s / 10 MB inline limit), and transcribes the whole utterance
/// on [stop] via the injected [transcribe] callback (wired to the backend
/// proxy). [partials] is empty — cloud is batch, no interim text. A
/// [SilenceDetector] drives auto-submit exactly as on-device does.
class CloudSttEngine implements SttEngine {
  CloudSttEngine({
    required this.silenceSeconds,
    required this.transcribe,
    this.maxBufferSeconds = 60,
  });

  final double silenceSeconds;
  final int maxBufferSeconds;

  /// Posts headerless LINEAR16 PCM and returns the transcript (throws on error).
  final Future<String> Function(Uint8List pcm, int sampleRate) transcribe;

  final _recorder = AudioRecorder();
  final _partials = StreamController<String>.broadcast();
  final _buffer = BytesBuilder(copy: false);
  SilenceDetector? _silence;
  StreamSubscription? _micSub;
  void Function()? _onAutoSubmit;
  bool _capped = false;
  int get _maxBytes => maxBufferSeconds * _kSampleRate * 2;

  @override
  Stream<String> get partials => _partials.stream;

  @override
  Future<void> start({void Function()? onAutoSubmit}) async {
    _onAutoSubmit = onAutoSubmit;
    _silence = onAutoSubmit == null
        ? null
        : SilenceDetector(
            sampleRate: _kSampleRate, silenceSeconds: silenceSeconds);
    final mic = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: 1,
      androidConfig:
          AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
    ));
    _micSub = mic.listen(_ingest);
  }

  /// Test seam: feed PCM as if from the mic, without `record`.
  @visibleForTesting
  void ingestForTest(Uint8List bytes) => _ingest(bytes);

  void _ingest(Uint8List bytes) {
    if (_capped) return;
    if (_buffer.length + bytes.length >= _maxBytes) {
      // Take up to the cap, then flush via auto-submit.
      final room = _maxBytes - _buffer.length;
      if (room > 0) _buffer.add(Uint8List.sublistView(bytes, 0, room));
      _capped = true;
      _onAutoSubmit?.call();
      return;
    }
    _buffer.add(bytes);
    final silence = _silence;
    if (silence != null && silence.addPcm(_pcm16ToFloat32(bytes))) {
      _capped = true; // stop feeding the detector after it fires
      _onAutoSubmit?.call();
    }
  }

  @override
  Future<SttResult> stop() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    final pcm = _buffer.toBytes();
    if (pcm.isEmpty) return const SttResult(transcript: '');
    try {
      final text = await transcribe(pcm, _kSampleRate);
      return SttResult(transcript: text.trim());
    } catch (e) {
      return SttResult(transcript: '', ok: false, error: '$e');
    }
  }

  @override
  Future<void> dispose() async {
    await _micSub?.cancel();
    _micSub = null;
    if (!_partials.isClosed) await _partials.close();
    _recorder.dispose();
  }

  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}
```

> Add `import 'package:flutter/foundation.dart';` for `@visibleForTesting`.

- [ ] **Step 4: Run to verify pass** — `cd hearty_app && flutter test test/core/stt/cloud_stt_engine_test.dart` (PASS, 3 tests).

- [ ] **Step 5: Analyze + commit**

```bash
git add hearty_app/lib/core/stt/cloud_stt_engine.dart hearty_app/test/core/stt/cloud_stt_engine_test.dart
git commit -m "feat(stt): CloudSttEngine (record mic + 60s PCM buffer + backend transcribe)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## C2 — Selection policy + wire into `VoiceNotifier`

### Task C2.1: `SttEngineSelector` (pure)

**Files:**
- Create: `hearty_app/lib/core/stt/stt_engine_selector.dart`
- Test: `hearty_app/test/core/stt/stt_engine_selector_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/stt_engine_selector.dart';

void main() {
  group('SttEngineSelector.useCloud', () {
    test('cloud only when online AND the setting is on', () {
      expect(SttEngineSelector.useCloud(online: true, useCloudWhenOnline: true),
          isTrue);
      expect(SttEngineSelector.useCloud(online: true, useCloudWhenOnline: false),
          isFalse); // user prefers on-device
      expect(SttEngineSelector.useCloud(online: false, useCloudWhenOnline: true),
          isFalse); // offline → on-device
      expect(
          SttEngineSelector.useCloud(online: false, useCloudWhenOnline: false),
          isFalse);
    });
  });
}
```

- [ ] **Step 2: Implement**

```dart
/// Decides whether a capture session should use the cloud engine.
/// Pure so the policy is unit-tested; engine construction (which touches
/// `record`/network) is the thin glue in VoiceNotifier._selectEngine.
class SttEngineSelector {
  static bool useCloud({
    required bool online,
    required bool useCloudWhenOnline,
  }) =>
      online && useCloudWhenOnline;
}
```

- [ ] **Step 3: Run + commit**

```bash
cd hearty_app && flutter test test/core/stt/stt_engine_selector_test.dart
git add hearty_app/lib/core/stt/stt_engine_selector.dart hearty_app/test/core/stt/stt_engine_selector_test.dart
git commit -m "feat(stt): SttEngineSelector — cloud iff online AND setting on

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task C2.2: Async engine selection in `VoiceNotifier`

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`

Change the engine-creation seam so production selects cloud/on-device at session open while the injected test factory path is unchanged.

- [ ] **Step 1: Make `engineFactory` nullable and add selection**

In the constructor, add params and stop defaulting the factory to a hard-coded `OnDeviceSttEngine`:

```dart
    SttEngine Function()? engineFactory,
    bool useCloudWhenOnline = true,
    Future<bool> Function()? isOnline, // injectable for tests
    ...
  })  : _engineFactory = engineFactory,        // nullable now
        _useCloudWhenOnline = useCloudWhenOnline,
        _isOnline = isOnline ?? _defaultIsOnline,
        ...
```

Fields + helpers:

```dart
  final SttEngine Function()? _engineFactory;
  final bool _useCloudWhenOnline;
  final Future<bool> Function() _isOnline;
  final double _silenceSeconds; // capture autoSubmitSilenceSeconds in a field

  static Future<bool> _defaultIsOnline() async {
    final r = await Connectivity().checkConnectivity();
    return r.any((x) => x != ConnectivityResult.none);
  }

  Future<SttEngine> _selectEngine() async {
    final online = await _isOnline();
    if (SttEngineSelector.useCloud(
        online: online, useCloudWhenOnline: _useCloudWhenOnline)) {
      return CloudSttEngine(
        silenceSeconds: _silenceSeconds,
        transcribe: (pcm, sr) =>
            _ref!.read(heartyApiClientProvider).transcribe(pcm: pcm, sampleRate: sr),
      );
    }
    return OnDeviceSttEngine(silenceSeconds: _silenceSeconds);
  }
```

In `_openSession`, replace `final engine = _engineFactory();` with:

```dart
    final engine = _engineFactory != null ? _engineFactory!() : await _selectEngine();
```

> Add imports: `package:connectivity_plus/connectivity_plus.dart`, `../../../core/stt/cloud_stt_engine.dart`, `../../../core/stt/stt_engine_selector.dart`. Keep the existing `on_device_stt_engine.dart` import.

> **Guard note:** `_selectEngine()` adds another `await` inside `_openSession` before the engine exists. The post-await dismiss/idle guard already in `_openSession` (it re-checks `mounted` + status before creating the engine) still sits after this await — keep it there. `_ref!` is safe on the production path (the real provider always passes `ref`); tests that exercise selection inject `engineFactory` or pass `ref` explicitly.

- [ ] **Step 2: Add lifecycle tests for the cloud path** (injected factory returning a `FakeSttEngine` already covers the lifecycle; add selection-wiring coverage via `isOnline` + a real `CloudSttEngine` is NOT needed — selection is unit-tested in C2.1). Add one test that the notifier still drives a cloud-style engine (no partials) to thinking on auto-submit:

```dart
    test('a partial-less (cloud-style) engine still auto-submits to thinking',
        () async {
      final n = c(container); // FakeSttEngine emits no partials by default
      n.startListening();
      await pump();
      h.latest!.nextTranscript = 'i had an iq bar';
      h.latest!.fireAutoSubmit();
      await pump();
      expect(container.read(voiceProvider).status, VoiceStatus.thinking);
      expect(container.read(voiceProvider).transcript, 'i had an iq bar');
    });
```

> The existing `FakeSttEngine` already models a no-partials batch engine (you only call `emitPartial` when you want partials), so this needs no new fake. The `engineFactory`-injection tests from Phase B continue to pass unchanged because `_engineFactory != null` short-circuits `_selectEngine`.

- [ ] **Step 3: Run the voice suite + analyze**

Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart && flutter analyze lib/features/voice/providers/voice_provider.dart`
Expected: PASS / clean.

- [ ] **Step 4: Commit**

```bash
git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "feat(voice): select cloud vs on-device per connectivity + useCloudWhenOnline

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## C3 — Runtime fallback + device verification

### Task C3.1: Surface cloud failure as manual/text fallback

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`

`CloudSttEngine.stop()` returns `SttResult(ok:false)` on a transcribe failure. `submit()` currently only checks `transcript.isNotEmpty`. Make it honour `ok`: on a failed result, do **not** advance to thinking with an empty transcript — drop to the manual/text fallback so the user can re-record or type (the captured audio is lost; that is the stated v1 limitation).

- [ ] **Step 1: Failing test**

```dart
    test('a failed cloud transcription drops to manual, not empty thinking',
        () async {
      final n = c(container);
      n.startListening();
      await pump();
      h.latest!.nextResultOk = false; // FakeSttEngine: simulate transcribe fail
      h.latest!.fireAutoSubmit();
      await pump();
      expect(container.read(voiceProvider).status, isNot(VoiceStatus.thinking));
      expect(container.read(voiceProvider).micPhase, MicPhase.paused);
    });
```

> Add `bool nextResultOk = true;` to `FakeSttEngine` and have `stop()` return `SttResult(transcript: nextTranscript, ok: nextResultOk)`.

- [ ] **Step 2: Implement** — in `submit()`, after the status re-check:

```dart
    if (!result.ok) {
      _pauseForManual();           // re-record / type; audio is lost (v1 limit)
      return;
    }
    final text = result.transcript.trim();
    if (text.isNotEmpty) setTranscript(text);
    setThinking();
```

- [ ] **Step 3: Run + analyze + commit**

```bash
cd hearty_app && flutter test test/features/voice/voice_provider_test.dart && flutter analyze
git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/voice_provider_test.dart hearty_app/test/core/stt/fake_stt_engine.dart
git commit -m "fix(voice): failed cloud transcription falls back to manual, not empty submit

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task C3.2: DEVICE VERIFY (gate)

> Requires: `GOOGLE_STT_API_KEY` set on the backend; the 122 MB on-device model pushed (for the offline leg); `make run`.

- [ ] **Online (cloud) — END-TO-END CONTRACT:** Flow 1 — "Hey Hearty" → "I had an IQ bar" → confirm the **cloud transcript is actually correct** (the open-vocab brand the on-device model fumbled). This is the only thing that proves the base64 → `audio.content` → Google LINEAR16/sample-rate contract round-trips — the unit tests cover the selector boolean and buffer logic but **never the real round trip**. Also confirm auto-submit ~2.5 s after silence and that the `stop()` → network round-trip **does not look hung** (lands in thinking within the timeout).
- [ ] **Airplane mode (on-device):** same phrase → confirm it falls back to the on-device engine and still logs (lower accuracy expected).
- [ ] **Mid-session drop:** start online, kill network before stop → confirm it drops to the **text field** (not a stuck spinner, not an empty submit). NOTE: on the **wake-word/listening** screen `_pauseForManual` only surfaces the "Or type here…" field — the tap-to-talk button renders only under `awaitingFollowUp`, not `listening` (pre-existing from B1.5; real tap-to-talk-under-listening is Plan D). So verify the **text** fallback specifically here.
- [ ] **Empty/garbage audio:** stay silent or make noise → confirm it does **not** hang in thinking (drops to manual) — the cloud-empty-transcript dead-spinner guard.
- [ ] **`useCloudWhenOnline=false`:** (temporarily pass `false` in the provider) confirm on-device is used even when online.
- [ ] No ANR; one ding; half-duplex — all still hold from Phase B.

- [ ] **Commit** any device-driven tweaks; otherwise C is done.

---

## Self-review

- **Spec coverage (P2):** `/api/transcribe` proxy (C0 ✓), `CloudSttEngine` batch with empty partials (C1 ✓), client-side silence detector on the cloud path too (C1 — reuses `SilenceDetector` ✓), selection policy + `useCloudWhenOnline` (C2 ✓), network fallback (C3.1 ✓, with the audio-loss limitation stated), key stays server-side (C0 ✓). Deferred-by-design: persisted `useCloudWhenOnline` setting + UI, "Transcribing…" micro-state, audio queuing / on-device re-decode (all Plan D / follow-up).
- **Two pre-settled decisions honoured:** 60 s buffer cap ties to Google's sync limit (C1.2 `maxBufferSeconds`); factory reaches the API client via the `transcribe` closure in `_selectEngine` while the synchronous injected `engineFactory` test seam is preserved (C2.2).
- **Type/name consistency:** `SttEngine.start({onAutoSubmit})`/`stop()→SttResult`/`partials`/`dispose()` — `CloudSttEngine` implements the same interface as `OnDeviceSttEngine`/`FakeSttEngine`. `SttResult.ok` (defined Phase B) is finally consumed (C3.1). `transcribe(pcm, sampleRate)` callback signature matches `HeartyApiClient.transcribe(pcm:, sampleRate:)` (C1.1) and the `_selectEngine` wiring (C2.2). Selector boolean `useCloud(online, useCloudWhenOnline)` defined C2.1, used C2.2.
- **Risk note:** C3.2 is the device gate — the cloud round-trip latency/UX (spec §11.3) and the connectivity-says-online-but-backend-unreachable case (why C3.1's runtime fallback exists) are only fully exercised on device.
