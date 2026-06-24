# Hearty — Master Specification

**Version:** 1.0  
**Date:** 2026-05-04  
**Status:** Active

---

## 1. Project Vision and Goals

**Hearty** is a personal food and symptom tracking application. Users log what they eat and how they feel via voice, text, or photos — with as little friction as possible. Over time, AI surfaces correlations between foods and health outcomes in plain language.

**Core goals:**

- Minimal logging friction: a single sentence or a voice clip should be enough
- AI does the heavy lifting: structure extraction, pattern detection, correlation surfacing
- Never block a log: if nutritional data is unavailable, log the entry anyway and note the gap
- Honest about uncertainty: confidence scores on triggers, no false precision
- Health-adjacent only: the wake word summons Hearty; non-health queries are handed off to the user's configured assistant
- Configurable notifications: gentle nudges by default, fully user-controlled

---

## 2. Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Mobile App | Flutter (Android primary, iOS same codebase later) | Mobile-first; Phase 2 |
| Web Dashboard | React + Vite + TailwindCSS + Recharts | Secondary; Phase 3 |
| Backend API | FastAPI (Python) | REST, auto-generated OpenAPI docs; LiteLLM for provider-agnostic LLM calls (Claude default, Gemini/GPT-4 swappable) |
| MCP Server | Node.js + `@modelcontextprotocol/sdk` | Claude Desktop / mobile / web integration |
| Database | Supabase (PostgreSQL + Auth + RLS + Storage) | All user data; Phase 1 |
| Auth | Supabase Auth — Google OAuth (Android), magic link (web) | Phase 1 |
| File Storage | Supabase Storage | Food photos |
| Hosting | Google Cloud Run (FastAPI, scale-to-zero) + Vercel (web) | Deployed — see docs/DEPLOYMENT.md |
| PDF Export | `react-pdf` or `pdfmake` | Doctor-sharing format |
| Charting | Recharts | Web dashboard only |
| TTS / Voice | Flutter TTS + platform STT; Porcupine wake word as foreground service; Claude voice mode via MCP | Porcupine foreground service; no VoiceInteractionService |

---

## 3. System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interfaces                         │
│  Flutter Android App  │  React Web Dashboard  │  Claude / MCP   │
└──────────┬────────────┴──────────┬────────────┴────────┬────────┘
           │                       │                      │
           │ REST (JWT Bearer)      │ REST (JWT Bearer)    │ MCP tools
           ▼                       ▼                      ▼
┌──────────────────────┐  ┌───────────────────┐  ┌──────────────────┐
│   FastAPI REST API   │  │   FastAPI REST API │  │ Node.js MCP Server│
│  (Python, deployed)  │  │  (same instance)   │  │ (user-installed)  │
└──────────┬───────────┘  └────────┬───────────┘  └────────┬─────────┘
           │                       │                        │
           └───────────────────────┴────────────────────────┘
                                   │
                          Supabase client (service key / RLS-scoped)
                                   │
                    ┌──────────────▼──────────────────┐
                    │         Supabase Platform        │
                    │  PostgreSQL  │  Auth  │  Storage │
                    └─────────────────────────────────-┘
```

### Data Flow: Voice Input → Response

1. User activates Hearty via wake word ("Hey Hearty") or taps mic
2. Flutter STT (or Claude voice mode) converts speech to text
3. Raw text sent to MCP Server tool call (`log_meal`, `log_symptoms`, etc.) or FastAPI endpoint
4. FastAPI / MCP Server calls Claude API to extract structured data from raw text
5. Structured record written to Supabase via Supabase client (RLS enforced)
6. AI formulates a natural language response; if offline queue used, sync status noted
7. Response returned to user via TTS or text display
8. 30–90 minutes later (configurable), notification triggers symptom follow-up

### Data Flow: Photo Input

1. User captures or selects photo; app prompts for type (or infers):
   - **Food plate** → Claude Vision API extracts food items
   - **Barcode** → ML Kit scan → food database lookup pipeline
   - **Nutrition label** → OCR → structured macros
   - **Food label / packaging** → OCR → brand + ingredients
2. Extracted data attached to meal record as `foods` JSONB and stored photo URL
3. Processing status tracked in `food_log_photos`

### Food Lookup Pipeline (tiered, never blocks logging)

1. Barcode → USDA FoodData Central / Open Food Facts
2. Restaurant name → restaurant nutrition DB (Nutritionix, Spoonacular)
3. Web search → AI parses result
4. AI estimate from description alone
5. Honest fallback: log entry with `data_source: "unknown"`, note gap in UI

---

## 4. Guiding Principles

| Principle | Implementation |
|---|---|
| Free-form input always accepted | Raw text stored; AI extracts structure after the fact |
| AI does heavy lifting | Claude extracts food items, severity, onset from natural language |
| Never block a log | Missing nutrition data → log anyway with `data_source: "unknown"` |
| Honest about gaps | Confidence scores shown on triggers; uncertain data flagged in UI |
| Wake word is health-adjacent only | Non-health queries forwarded to user's configured default assistant |
| Configurable notifications | Defaults: gentle nudge 30–90 min post-meal; all settings user-controlled |
| Offline-first | Flutter queues logs locally; syncs on reconnect; UI shows sync status |
| No medical advice | AI provides pattern observations, never diagnoses |
| Privacy by default | All data RLS-scoped; doctor PDF export is the only share mechanism |
| LLM provider agnostic | LiteLLM abstraction — default Claude, swappable to Gemini or GPT-4 via env var |
| Honest about data gaps | No calorie estimation from photos — calories only from barcodes or nutrition labels |

---

## 5. Sub-Spec Index

| # | Spec File | Scope | Phase |
|---|---|---|---|
| 01 | `hearty-01-database.md` | Supabase schema, RLS, indexes, migration | Phase 1 |
| 02 | `hearty-02-mcp-server.md` | Node.js MCP server, tools, Hearty persona | Phase 1 |
| 03 | `hearty-03-rest-api.md` | FastAPI endpoints, AI extraction, auth webhook | Phase 1 |
| 04 | `hearty-04-android-app.md` | Flutter Android, wake word, voice I/O, offline, camera | Phase 2 |
| 05 | `hearty-05-web-dashboard.md` | React + Vite dashboard, charts, PDF export | Phase 3 |
| 06 | `hearty-06-ai-vision.md` | Photo processing pipeline, OCR, food plate vision | Phase 4 |
| 07 | `hearty-07-food-intelligence.md` | Tiered food lookup, barcode, web search, AI estimate | Phase 4 |
| 08 | `hearty-08-health-profile.md` | Allergens, conditions, protocols, AI enrichment | Phase 1 |
| 09 | `hearty-09-ios-app.md` | Flutter iOS, Siri Shortcuts, App Store prep | Future |
| 10 | `hearty-10-health-connect.md` | Android health data read/write integration | Future |
| 11 | `hearty-11-knowledge-freshness.md` | Health research RAG, food DB sync, server-side updates | Future |
| 12 | `hearty-12-local-llm.md` | Ollama/LM Studio local LLM support, Cloudflare Tunnel | Future (Moonshot) |

---

## 6. Phase Roadmap

| Phase | Name | Deliverables | Key Sub-Specs |
|---|---|---|---|
| Phase 1 | Foundation | Supabase DB + RLS, MCP Server, FastAPI REST API, Health Profile | 01, 02, 03, 08 |
| Phase 2 | Android App | Flutter Android, voice + wake word, notifications, offline sync | 04 |
| Phase 3 | Web Dashboard | React + Vite dashboard, charts, PDF export | 05 |
| Phase 4 | AI Intelligence | Vision AI, barcode, OCR, food lookup pipeline | 06, 07 |
| Future | Expansion | iOS (same Flutter codebase), Health Connect, knowledge freshness | 09, 10, 11 |
| Moonshot | Local LLM | Ollama/LM Studio via Cloudflare Tunnel or local FastAPI | 12 |

---

## 7. Cross-Cutting Concerns

### 7.1 Authentication

- **Android:** Google OAuth via Supabase Auth; Flutter uses `supabase_flutter` package
- **Web:** Magic link email auth via Supabase Auth
- **API:** All FastAPI and MCP Server requests authenticated with Supabase JWT
- **Token flow:** Flutter/web gets JWT from Supabase after auth → attaches as `Authorization: Bearer <token>` on all API calls
- **Service role key:** FastAPI and MCP Server use service role key for admin operations; user-facing operations go through RLS-scoped client

### 7.2 Offline Strategy

- Flutter maintains a local SQLite cache (via `drift` or `sqflite`)
- Writes while offline: record stored locally + queued in `offline_queue` table (once online)
- On reconnect: queue processed in order; conflicts resolved by `logged_at` timestamp (last-write-wins at field level)
- UI shows per-entry sync badge: synced / pending / failed
- Reads while offline: served from local cache; stale data flagged with last-sync timestamp

### 7.3 Row Level Security Model

All tables enforce RLS. The base policy on every user-data table:

```sql
-- Template: users see only their own rows
CREATE POLICY "owner_only" ON <table>
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

Service role key (used by FastAPI and MCP Server backend) bypasses RLS for batch operations and trend analysis; it is never exposed to client-side code.

### 7.4 Notification System

- **Post-meal nudge:** Triggered 30–90 min after a meal is logged (default 60 min); configurable per-user in `notification_preferences`
- **Daily check-in:** Optional morning wellbeing snapshot prompt; off by default
- **Weekly digest:** Optional Sunday summary of the week's patterns; off by default
- **Custom triggers:** User can define additional notification rules (e.g., "remind me after dinner only")
- **Delivery:** Push notifications via Firebase Cloud Messaging (Android); web push for browser; in-app for active sessions
- **Quiet hours:** Respects user-defined quiet window; nudges deferred until window ends
- **Never nag:** If symptom log already received post-meal, nudge is suppressed

---

*See individual sub-specs for detailed implementation guidance.*
