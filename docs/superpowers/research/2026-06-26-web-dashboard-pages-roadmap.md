# Web Dashboard Pages — Roadmap (Pre-Brainstorm Research)

**Status:** Research / options memo (NOT a spec or design). Input for a future brainstorm.
**Date:** 2026-06-26
**Scope:** `hearty-web/` React/Vite dashboard pages.

---

## ⚠️ Headline correction: the pages are NOT placeholders

The premise for this memo was "Journal, Trends, Experiments, Reports, Profile, Settings are `ComingSoon` placeholders to build." **That is no longer true.** Verified against the code:

- `hearty-web/src/App.tsx:6-14, 22-31` imports and routes **every** page to its **real** component. `ComingSoon` is **not imported anywhere** in `App.tsx` — `ComingSoon.tsx` is an orphaned 8-line file.
- All six named pages plus Dashboard, Conversation, and Admin are implemented (line counts below), each with tests (`*.test.tsx`).
- The stale source of the premise: **`hearty-web/README.md:5`** still says "Plan 1 — Foundation … Journal, Trends, Experiments, Reports, Profile, and Settings routes are placeholders (`ComingSoon`)." Meanwhile the git history is on **"Plan 6 — web dashboard integration"** (recent commits: web dashboard integration checklist, Vercel runbook, CI for web). **The README is out of date; the pages shipped.**

So this is no longer a "build the placeholder pages" roadmap. It is reframed as an **enhancement / polish priority** roadmap: what each page already does, what powers it, and where the gaps are.

> *Note: this memo reflects the implemented & route-wired code (read), not a runtime functional QA of each page. A live audit is out of scope for a pre-brainstorm memo.*

---

## 1. Per-page current state

For each: route + file (line count), what it does, the hooks/endpoints powering it (verified in `hearty-web/src/lib/api.ts` and `hearty-web/src/hooks/`), candidate v2 enhancements, effort, dependencies.

### Dashboard — `/`, `/dashboard` · `Dashboard.tsx` (~88)
- **Now:** logs meals/symptoms, today's timeline, week summary, strongest signal.
- **Powered by:** `useTodayMeals`/`useTodaySymptoms` (`GET /api/meals`, `GET /api/symptoms`), `useWeekSummary` (`GET /api/summary`), `useTrends` (`GET /api/trends`); `POST /api/meals`.
- **v2 ideas:** richer quick-log, symptom quick-entry parity, empty-state polish.
- **Effort:** S · **Deps:** none.

### Journal — `/journal` · `Journal.tsx` (~75)
- **Now:** paginated meal/symptom history with filters (date range, meal type, symptom type, keyword).
- **Powered by:** `useJournalFilters` (URL state), `useJournalMeals` (`GET /api/meals` with filters/limit/offset).
- **v2 ideas:** inline edit/delete (endpoints `PATCH`/`DELETE /api/meals/{id}` & `/api/symptoms/{id}` **already exist**, may be underused here), combined meal+symptom timeline view, saved filters.
- **Effort:** S–M · **Deps:** endpoints exist.

### Trends — `/trends` · `Trends.tsx` (~135)
- **Now:** signal analysis with period selector (7/30/90d), trend hero, signal cards, frequency charts; trigger re-analysis; record signal verdicts.
- **Powered by:** `useTrends`, `useAnalyze` (`POST /api/trends/analyze`), `useAnalyzeStatus` (`GET /api/trends/analyze/status`), `useSignalVerdict` (`POST /api/trends/signal-verdict`); reads `/api/symptoms`, `/api/meals`.
- **v2 ideas:** deeper charts, multi-year view (cf. spec `2026-06-14-multi-year-trends-design.md`), surface Layer-1 RAG research grounding in the UI.
- **Effort:** M · **Deps:** analysis endpoints exist; multi-year may need backend work.

### Conversation — `/trends/chat` · `Conversation.tsx` (~111)
- **Now:** AI trends chat; proposes verdicts/experiments; autoscroll.
- **Powered by:** `useConversation` (`POST /api/trends/conversation`); `POST /api/trends/signal-verdict`, `POST /api/experiments`.
- **v2 ideas:** streaming responses, conversation history persistence/recall.
- **Effort:** M · **Deps:** streaming would need backend support.

### Experiments — `/experiments` · `Experiments.tsx` (~53)
- **Now:** active experiments list with evaluate / abandon / restart / ack-nudge.
- **Powered by:** `useActiveExperiments` (`GET /api/experiments/active`), `useExperimentActions` (`POST /api/experiments/{id}/evaluate|abandon|restart|ack-nudge`).
- **v2 ideas:** create-experiment-from-scratch UI (`POST /api/experiments` exists but creation flow may be chat-only), historical/completed experiments view, results visualization.
- **Effort:** S–M · **Deps:** create endpoint exists; "completed" list may need a new query param/endpoint.

### Reports — `/reports` · `Reports.tsx` (~83)
- **Now:** data export (CSV / JSON / PDF) with date-range picker + summary preview.
- **Powered by:** `getSummary` (`GET /api/summary`), `exportCsv`/`exportJson` (`GET /api/export/csv|json`), `exportPdf` (`POST /api/export/pdf`).
- **v2 ideas:** scheduled/emailed reports, shareable clinician report, richer PDF.
- **Effort:** M · **Deps:** scheduling/email would be new backend infra.

### Profile — `/profile` · `Profile.tsx` (~139)
- **Now:** health profile mgmt — allergens, intolerances, conditions, dietary protocols (severity/details), seeded from defaults.
- **Powered by:** `useHealthProfile`/`useSaveHealthProfile` (`GET`/`PUT /api/health-profile`), `useHealthProfileDefaults` (`GET /api/health-profile/defaults`).
- **v2 ideas:** validation UX polish, condition→RAG linkage visibility (Layer 1 filters research by these conditions).
- **Effort:** S · **Deps:** endpoints exist.

### Settings — `/settings` · `Settings.tsx` (~121)
- **Now:** preferences (notifications, nudge delays, conversation style, check-in slots), account mgmt, data export, account deletion.
- **Powered by:** `usePreferences`/`useSavePreferences` (`GET`/`PUT /api/preferences`); `exportJson`, `deleteAccount` (`DELETE /api/account`).
- **v2 ideas:** "knowledge / food data last updated" trust surface (Spec 11 §5.1 — *needs backend from Layer 2 memo*), notification-channel detail.
- **Effort:** S (UI) · **Deps:** the freshness surface depends on Layer 2 work.

### Admin — `/admin` · `Admin.tsx` (~360)
- **Now:** subscriber/license mgmt, app settings (signup policy), system health, LLM test, **knowledge-base CRUD** (Layer 1 shipped here).
- **Powered by:** `useAdminUsers`/`useAdminActions`, `useAppSettings`/`useUpdateAppSettings`, `useHealth`/`useTestLlm`, `useKnowledge`/`useKnowledgeActions` over `/api/admin/*`.
- **v2 ideas:** this is the natural home for the **Layer 3 prompt editor** (sibling memo) and **Layer 2 food gap-tracking / freshness dashboard**.
- **Effort:** depends on those layers · **Deps:** Layer 2 / Layer 3 backends.

---

## 2. Endpoint inventory (source of truth: `hearty-web/src/lib/api.ts`)

Meals/symptoms: `GET/POST /api/meals`, `PATCH/DELETE /api/meals/{id}`; `GET /api/symptoms`, `PATCH/DELETE /api/symptoms/{id}`.
Trends: `GET /api/trends`, `POST /api/trends/analyze`, `GET /api/trends/analyze/status`, `POST /api/trends/signal-verdict`, `POST /api/trends/conversation`.
Summary/export: `GET /api/summary`; `GET /api/export/csv|json`, `POST /api/export/pdf`.
Experiments: `POST /api/experiments`, `GET /api/experiments/active`, `POST /api/experiments/{id}/evaluate|abandon|restart|ack-nudge`.
Profile/prefs/account: `GET/PUT /api/health-profile`, `GET /api/health-profile/defaults`; `GET/PUT /api/preferences`; `DELETE /api/account`; `GET /api/license/status`.
Admin: `GET /api/admin/users`; license grant/revoke/reactivate/patch; `GET/PUT /api/admin/settings`; `GET /api/admin/health`, `POST /api/admin/health/llm-test`; `GET/POST/DELETE/PATCH /api/admin/knowledge`.

---

## 3. Recommended priority order (a recommendation, not a commitment)

Since nothing needs building from zero, the order is about **highest-leverage enhancement** and **unblocking the other two memos**:

1. **Fix the stale README first (trivial).** It actively misleads — anyone reading it (including this task) believes the dashboard is barely started. One-line correction; do it regardless of anything else.
2. **Journal inline edit/delete** — endpoints already exist (`PATCH/DELETE`), small UI work, immediate user value (correcting logged data is a core journaling need). Lowest effort, clearest win.
3. **Settings/Admin freshness & config surfaces** — but these are *downstream of Layer 2 (food freshness) and Layer 3 (prompt store)*; sequence them after those backends land. Admin is already the proven home for such panels (knowledge-base CRUD lives there).
4. **Trends depth (multi-year / RAG grounding visibility)** — higher value but more backend-coupled; brainstorm whether the backend is ready.
5. **Reports scheduling / clinician share** and **Conversation streaming** — most backend-heavy; later.

**First move:** correct the README, then Journal edit/delete as the cheapest user-visible improvement; hold the Admin/Settings panels until Layer 2/3 decisions are made.

---

## 4. Open questions for the brainstorm

1. **Is there a *runtime* gap behind the code?** This memo confirms pages are implemented & wired, not that every feature works end-to-end in prod — does the brainstorm need a quick functional pass first?
2. **What's actually missing vs polish?** Which "v2 ideas" above are real gaps users feel vs nice-to-haves?
3. **Coupling to Layer 2/3:** the most valuable Admin/Settings additions depend on the other two memos — sequence accordingly?
4. **README/doc hygiene:** who owns keeping `hearty-web/README.md` and the plan docs in sync with shipped reality?
