# Hearty Spec 12 — Local LLM Support

**Version:** 1.0  
**Date:** 2026-05-04  
**Status:** Future (Moonshot)  
**Phase:** Post Phase 4

---

## 1. Overview

Local LLM support allows Hearty to run its AI extraction, analysis, and food lookup entirely on-device or on a local server — eliminating API costs entirely. This is a moonshot phase requiring dedicated hardware and technical setup from the user.

Users who have capable hardware (a desktop or home server with sufficient RAM/VRAM) can run an Ollama or LM Studio instance alongside a local FastAPI backend. The Flutter app connects to this local stack either on the home network or globally via a Cloudflare Tunnel. When configured, every meal log, symptom extraction, and food lookup runs locally at zero ongoing API cost.

---

## 2. Supported Runtimes

Both runtimes expose an OpenAI-compatible API and are already supported by LiteLLM via model string prefix.

| Runtime | Default API URL | Model Prefix | Notes |
|---|---|---|---|
| **Ollama** | `http://localhost:11434/v1` | `ollama/` | Simple CLI install, large model library, good scripting support |
| **LM Studio** | `http://localhost:1234/v1` | `lm_studio/` | GUI-based, easier for non-technical users; GGUF model downloads built in |

No backend code changes are required — LiteLLM routes to either runtime transparently based on the model string in `.env`.

---

## 3. Model Recommendations

### Structured output (meal / symptom extraction)

| Model | Size | VRAM / RAM needed | Notes |
|---|---|---|---|
| `llama3.3:70b` | 70B | ~40 GB | Recommended; reliable JSON output |
| `qwen2.5:72b` | 72B | ~42 GB | Strong alternative; excellent instruction following |
| 7B–13B models | — | ~8–10 GB | Not recommended for production — inconsistent structured output |

70B+ models produce reliable JSON consistently. Smaller models (7B–13B) are inconsistent with structured extraction and should not be used as the primary provider unless the user explicitly accepts degraded quality.

### Vision (food plate photos)

| Model | Size | VRAM / RAM needed | Notes |
|---|---|---|---|
| `llava:34b` | 34B | ~22 GB | Best local vision quality |
| `llama3.2-vision:11b` | 11B | ~8 GB | Acceptable quality; lower hardware bar |

### Hardware requirements summary

- **70B text model**: ~40 GB RAM or GPU VRAM
- **11B vision model**: ~8 GB RAM or GPU VRAM
- Running both simultaneously requires a machine with 48 GB+ available memory

### Quality caveat

Local models produce less reliable structured extraction than Claude or Gemini. This is a known and documented tradeoff. Hearty validates all extraction output and falls back gracefully when output is malformed — see Section 6.

---

## 4. Architecture Options

### Option A — Local FastAPI + Ollama (home network only)

```
┌──────────────────┐          ┌────────────────────────┐
│  Flutter App     │ ─ WiFi ─▶│  Local FastAPI          │
│  (Android)       │          │  (home server/desktop)  │
└──────────────────┘          └────────────┬───────────┘
                                            │
                                   ┌────────▼────────┐
                                   │  Ollama / LM Studio │
                                   │  (same machine)     │
                                   └─────────────────────┘
```

- FastAPI backend runs locally alongside Ollama on a home server or desktop
- Flutter app points to the local IP when on home WiFi (configurable in app settings: **"Local server URL"**)
- Falls back to cloud provider (Claude/Gemini) when away from home
- Zero API cost when on the home network

### Option B — Cloudflare Tunnel (accessible anywhere)

```
┌──────────────────┐    ┌─────────────────────┐    ┌────────────────────────┐
│  Flutter App     │───▶│  Cloudflare Tunnel   │───▶│  Local FastAPI + Ollama│
│  (anywhere)      │    │  (*.trycloudflare.com│    │  (home server)         │
└──────────────────┘    │   or named tunnel)   │    └────────────────────────┘
                        └─────────────────────┘
```

- FastAPI and Ollama run locally on the home server
- `cloudflared tunnel` exposes the FastAPI port to a stable public URL
- Free Cloudflare account required; no port forwarding or static IP needed
- Flutter app always connects via the Cloudflare tunnel URL regardless of network
- Zero API cost anywhere — requires the home server to remain running

---

## 5. LiteLLM Configuration

Since the backend already uses LiteLLM, switching to a local model is a pure `.env` change. No backend code modifications are required.

**Ollama example:**

```env
LLM_MODEL=ollama/llama3.3:70b
LLM_BASE_URL=http://localhost:11434/v1
```

**LM Studio example:**

```env
LLM_MODEL=lm_studio/llama-3.3-70b-instruct
LLM_BASE_URL=http://localhost:1234/v1
```

**Cloudflare Tunnel example (remote access):**

```env
LLM_MODEL=ollama/llama3.3:70b
LLM_BASE_URL=https://your-tunnel-name.trycloudflare.com/v1
```

The `LLM_API_KEY` variable can be omitted or set to a dummy value for local runtimes that do not require authentication.

---

## 6. Output Validation Requirement

Local models must pass through the same JSON validation layer as cloud providers. This validation is implemented in `ai_extraction.py`.

### Validation logic

```python
async def extract_with_validation(prompt: str, schema: dict, max_attempts: int = 2) -> dict | None:
    for attempt in range(max_attempts):
        raw = await litellm_complete(prompt)
        parsed = try_parse_json(raw)
        if parsed and validate_required_fields(parsed, schema):
            return parsed
        # On first failure, retry with a simpler, more constrained prompt
        prompt = build_fallback_prompt(prompt)
    # After max_attempts, log the raw input without structured extraction
    log_unstructured_entry(prompt)
    return None
```

### Behavior at each stage

| Attempt | Action |
|---|---|
| 1 | Send standard extraction prompt; validate required fields in response |
| 2 | Retry with a simpler, more constrained prompt (fewer fields, explicit JSON instruction) |
| After 2 failures | Log the raw input without structured extraction; flag entry in UI as "needs review" |

This graceful degradation ensures that even if the local model fails to produce valid JSON, the user's log entry is never lost. The raw text is stored and can be re-processed later (manually or when a better model is available).

---

## 7. Phase Prerequisites

- Phase 1–4 complete and stable
- User has a machine capable of running 70B models (~40 GB RAM), or explicitly accepts reduced extraction quality with a smaller model
- Cloudflare account (free tier) if remote access via Cloudflare Tunnel is desired
- User understands this is a self-hosted configuration requiring manual setup and maintenance

---

*This spec is intentionally forward-looking. Implementation details may change as local model capabilities evolve.*
