# Hearty — Local LLM Support (Spec 12) — Living Plan

**Spec:** [`hearty-12-local-llm.md`](../specs/2026-05-04-hearty-12-local-llm.md)  
**Roadmap Phase:** Moonshot — Post Phase 4  
**Plan Status:** 🔴 Not Started  
**Last Updated:** 2026-05-04  
**Last Verified Against Spec:** 2026-05-04 — re-verify if spec has changed since  
**Open Deviations:** 0

> **MOONSHOT SPEC — Re-verify thoroughly before execution.**  
> This is the most speculative plan in the Hearty roadmap. It requires dedicated hardware (a machine with 40 GB+ RAM or VRAM to run 70B models), self-hosted infrastructure, and ongoing operational maintenance by the user. Before beginning any phase, confirm all prerequisite specs are complete and re-evaluate whether current local LLM capabilities (Ollama, LM Studio, available 70B models) have caught up with or exceeded the assumptions made here. Model quality, APIs, and tooling in this space change rapidly.

---

## How to Use This Plan

1. Always start with **Phase 0** at the beginning of any new session on this plan
2. Find the first phase/task marked **🔴 Not Started**, mark it **🟡 In Progress**
3. Paste the phase's **Activation Prompt** into a new Claude Code session
4. Follow the steps — Claude will guide you through each one
5. At natural break points, Claude will tell you to run `/compact`; do so, then start a new session with the **Activation Prompt** at the top of the next phase
6. Mark completed phases **🟢 Completed** and log any deviations as a single line at the bottom

**Status key:** 🔴 Not Started · 🟡 In Progress · 🟢 Completed · ⚠️ Blocked · ↩️ Deviated

---

## Phase Summary

| Phase | Name | Status | Depends On | Type |
|---|---|---|---|---|
| 0 | Review & Align | 🔴 Not Started | Spec 03 complete | Claude (start of every session) |
| 1 | Local LLM Runtime Setup | 🔴 Not Started | Phase 0 | Manual |
| 2 | LiteLLM .env Configuration | 🔴 Not Started | Phase 1 | Claude |
| 3 | Network Connectivity | 🔴 Not Started | Phase 1 | Manual |
| 4 | Output Validation Layer | 🔴 Not Started | Phase 2 | Claude |
| 5 | Smoke Test | 🔴 Not Started | Phases 2–4 | Claude |

---

## Phase 0: Review & Align

**Status:** 🔴 Not Started  
**Goal:** Verify prerequisites are complete, confirm the local hardware meets requirements, and re-evaluate all local LLM tooling for currency before committing to this path.  
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty Local LLM plan.
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

IMPORTANT: This is a future/moonshot spec. Before detailing any tasks, verify
that all prerequisite specs are complete and that the technologies referenced
are still current — versions and APIs may have changed significantly since this
plan was written. Local LLM tooling in particular evolves extremely rapidly;
model recommendations, runtime APIs, and LiteLLM integration patterns from
2026-05-04 may be significantly outdated.

Working directory: /home/evan/projects/food-journal-assistant

Steps:

1. Read both files in full:
   - docs/superpowers/plans/2026-05-04-hearty-12-local-llm-plan.md
   - docs/superpowers/specs/2026-05-04-hearty-12-local-llm.md

2. Verify prerequisite specs are complete:
   - Spec 03 (REST API): check its plan file for 🟢 Completed status
   - If Spec 03 is not complete, this plan cannot proceed — report that clearly
   - Note: the spec also says "Post Phase 4." Confirm whether Phases 1–4 roadmap
     specs (01–08) are all complete, or document which are still in progress.

3. Hardware check — ask the user to confirm:
   - Available RAM or VRAM on the intended local machine
   - Whether a GPU is available and its VRAM capacity
   - Whether the machine can remain running as a home server
   - Whether Cloudflare Tunnel access is desired (Option B) or home-network-only
     (Option A) is sufficient
   Do not proceed past this check without hardware confirmation.

4. Re-verify current status of named technologies:
   - Ollama — current version; is `ollama/llama3.3:70b` still the recommended
     model for structured output, or is there a better current option?
   - LM Studio — current version; still using OpenAI-compatible API on port 1234?
   - LiteLLM — current version; `ollama/` and `lm_studio/` prefixes still valid?
   - `llava:34b` and `llama3.2-vision:11b` — still the recommended vision models,
     or have better options emerged?
   - Cloudflare Tunnel (`cloudflared`) — current version; free tier still available?
   - 7B–13B model quality for structured output — has this improved enough to
     reconsider the recommendation against using them?

5. Check the backend:
   - Locate ai_extraction.py (or equivalent) in the FastAPI backend
   - Confirm LiteLLM is already used for all LLM calls (no hardcoded Anthropic SDK)
   - Confirm CLAUDE_MODEL and LLM_BASE_URL environment variables exist or can be added

6. Spec drift check — the plan was written on 2026-05-04. Scan the spec for any
   changes to model recommendations, runtime APIs, or validation logic.
   List any conflicts found.

7. Report:
   - Prerequisites: Spec 03 complete or blocked; Phase 4 status
   - Hardware: confirmed specs or "awaiting user input"
   - Technology currency: any outdated models, versions, or integration patterns
   - Backend state: LiteLLM integration confirmed or work needed
   - Spec alignment: drift found, or "clean"
   - Next action: which phase to proceed with, or what to resolve first

Before running any command, verify it exists with --help or equivalent.
If a command doesn't behave as expected, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
```

**Deviation Log:** _None_

---

## Phase 1: Local LLM Runtime Setup

**Status:** 🔴 Not Started  
**Goal:** Install and configure Ollama or LM Studio on the local machine, download the chosen model(s), and verify the runtime serves the OpenAI-compatible API endpoint.  
**Depends on:** Phase 0 (hardware confirmed, runtime choice made)  
**Type:** Manual

**Key deliverables:**
- Chosen runtime (Ollama or LM Studio) installed and running
- Primary text model downloaded (70B recommended — confirm specific model at phase start)
- Vision model downloaded if food photo analysis is in scope for this phase
- OpenAI-compatible API endpoint verified reachable at expected local URL
- Runtime startup confirmed: model loads without errors, API returns a valid response

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 2: LiteLLM .env Configuration

**Status:** 🔴 Not Started  
**Goal:** Switch the FastAPI backend to use the local LLM endpoint by updating environment variables, with no backend code changes required.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- `LLM_MODEL` set to the correct runtime prefix and model name (e.g., `ollama/llama3.3:70b`)
- `LLM_BASE_URL` set to the local runtime endpoint
- `LLM_API_KEY` set to a dummy value or omitted as appropriate for the chosen runtime
- `CLAUDE_MODEL_FALLBACK` configured so rollback to cloud provider is one `.env` change
- FastAPI backend confirmed to route all LLM calls through the local endpoint

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 3: Network Connectivity

**Status:** 🔴 Not Started  
**Goal:** Configure either home-network-only access (Option A) or global access via Cloudflare Tunnel (Option B), and add a "Local server URL" setting to the Flutter app.  
**Depends on:** Phase 1  
**Type:** Manual

**Key deliverables:**
- Option A or Option B chosen and documented (decide at phase start based on user preference confirmed in Phase 0)
- If Option B: `cloudflared tunnel` installed, configured, and exposing FastAPI on a stable public URL
- Flutter app Settings: "Local server URL" field added so the user can configure the backend endpoint
- Fallback to cloud provider when local server is unreachable (on home network or tunnel down)
- Connection switching logic tested: app correctly uses local endpoint when reachable, cloud endpoint when not

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 4: Output Validation Layer

**Status:** 🔴 Not Started  
**Goal:** Ensure the `extract_with_validation` function in `ai_extraction.py` covers all local LLM failure modes — malformed JSON, missing required fields, and repeated extraction failures.  
**Depends on:** Phase 2  
**Type:** Claude

**Key deliverables:**
- `extract_with_validation` function confirmed to implement: attempt 1 with standard prompt → attempt 2 with simplified fallback prompt → log raw input on second failure
- Failed entries flagged in UI as "needs review" — never silently lost
- Raw unstructured text stored and re-processable when a better model is available
- Validation layer tested against known local model failure patterns (truncated JSON, extra prose, wrong field names)
- Test suite covers all three paths: valid extraction, retry-and-succeed, two-failure fallback

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 5: Smoke Test

**Status:** 🔴 Not Started  
**Goal:** Verify the complete local LLM path end-to-end: Flutter app → local FastAPI → Ollama/LM Studio → structured extraction → Supabase storage.  
**Depends on:** Phases 2–4  
**Type:** Claude

**Key deliverables:**
- Text meal log: submitted via Flutter, extracted by local model, stored correctly in Supabase
- Voice meal log: submitted via Flutter, extracted by local model, stored correctly
- Photo meal log (if vision model is configured): food identified by local vision model, result stored
- Intentional bad prompt submitted to verify fallback path triggers correctly
- Latency benchmarked and documented: local model response time vs cloud baseline
- Rollback verified: changing `.env` back to cloud provider restores full function without code changes

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X — changed X because Y`_

---

## Notes

- **Hardware is a hard prerequisite:** This entire plan is blocked without a machine capable of running 70B parameter models (~40 GB RAM/VRAM). Phase 0 will not advance without hardware confirmation.
- **LiteLLM already in the stack:** The spec's central premise is that no backend code changes are required — only `.env` changes. If LiteLLM is not the backend's LLM call layer when this phase starts, Phase 2 must be expanded to add it.
- **Quality tradeoff is explicit:** The spec acknowledges local models produce less reliable structured extraction than Claude or Gemini. This is a documented user acceptance decision, not a bug to fix. Phase 4 validation minimizes data loss, but does not eliminate quality degradation.
- **Cloud fallback is essential:** Phases 3 and 5 both depend on a clean cloud fallback path. Do not disable cloud provider configuration until local path is fully validated.
- **Model recommendations will be stale:** The `llama3.3:70b` and `qwen2.5:72b` recommendations were current as of 2026-05-04. Phase 0 must re-evaluate what the best available structured-output models are at execution time.
