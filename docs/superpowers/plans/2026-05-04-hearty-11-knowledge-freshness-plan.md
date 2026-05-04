# Hearty — Knowledge Freshness (Spec 11) — Living Plan

**Spec:** [`hearty-11-knowledge-freshness.md`](../specs/2026-05-04-hearty-11-knowledge-freshness.md)  
**Roadmap Phase:** Future Phase (implement progressively after Spec 03 REST API and Spec 07 Food Intelligence)  
**Plan Status:** 🔴 Not Started  
**Last Updated:** 2026-05-04  
**Last Verified Against Spec:** 2026-05-04 — re-verify if spec has changed since  
**Open Deviations:** 0

> **FUTURE PHASE — Re-verify before execution.**  
> This plan was written speculatively. Before beginning any phase, confirm that all prerequisite specs are complete and that all technologies named here (pgvector, NCBI E-utilities, Open Food Facts dump format, USDA FoodData Central JSON export, OpenAI embeddings, Supabase pg_cron, Celery) are still current. Data source APIs and embedding model options may have changed significantly since this plan was written.

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
| 0 | Review & Align | 🔴 Not Started | Specs 03 + 07 complete | Claude (start of every session) |
| 1 | RAG Corpus Setup | 🔴 Not Started | Phase 0 | Claude |
| 2 | Food Database Sync | 🔴 Not Started | Phase 0 | Claude |
| 3 | Server-Side Update Pipeline | 🔴 Not Started | Phase 1 | Claude |
| 4 | Freshness UI & User Notifications | 🔴 Not Started | Phases 1–3 | Mixed |

---

## Phase 0: Review & Align

**Status:** 🔴 Not Started  
**Goal:** Verify prerequisites are complete, confirm the spec and all named data sources are current, and identify which phase to begin.  
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty Knowledge Freshness plan.
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

IMPORTANT: This is a future/moonshot spec. Before detailing any tasks, verify
that all prerequisite specs are complete and that the technologies referenced
are still current — versions and APIs may have changed significantly since this
plan was written.

Working directory: /home/evan/projects/food-journal-assistant

Steps:

1. Read both files in full:
   - docs/superpowers/plans/2026-05-04-hearty-11-knowledge-freshness-plan.md
   - docs/superpowers/specs/2026-05-04-hearty-11-knowledge-freshness.md

2. Verify prerequisite specs are complete:
   - Spec 03 (REST API): check its plan file for 🟢 Completed status
   - Spec 07 (Food Intelligence): check its plan file for 🟢 Completed status
   - If either is not complete, report that clearly — this plan may still start
     (data collection can precede full AI integration), but note the dependency

3. Check database prerequisites — the spec requires several tables and extensions
   that should have been created in Spec 01. Verify in Supabase:
   - `pgvector` extension enabled
   - `knowledge_base` table exists (with `content_embedding vector(1536)` column)
   - `feature_flags` table exists
   - `health_metrics` table exists (shared with Spec 10)
   If any are absent, a new migration must be added before Phase 1 can begin.

4. Check the dev environment:
   - python --version  (need >= 3.10 for FastAPI backend)
   - git status
   - Confirm CLAUDE_MODEL is set as an environment variable (not hardcoded)

5. Re-verify current status of named technologies and data sources:
   - NCBI E-utilities API — still free, still accessible, same endpoint?
   - Open Food Facts weekly dump — format and URL still current?
     (world.openfoodfacts.org/data)
   - USDA FoodData Central JSON export — still quarterly releases?
   - OpenAI `text-embedding-3-small` — still available and cost-effective?
     Are there better/cheaper alternatives now?
   - Supabase pg_cron + Edge Functions — execution time limits still a concern
     for large data dumps?
   - Celery — current version; is it still the right choice if job complexity warrants it?

6. Spec drift check — the plan was written on 2026-05-04. Scan the spec for any
   changes to data source coverage, schema definitions, or curation process.
   List any conflicts found.

7. Report:
   - Prerequisites: which specs are complete or blocked
   - Database state: which tables/extensions exist or are missing
   - Environment: what is/isn't installed
   - Technology currency: any outdated or deprecated items
   - Spec alignment: drift found, or "clean"
   - Next action: which phase to proceed with, or what to resolve first

Before running any command, verify it exists with --help or equivalent.
If a command doesn't behave as expected, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
```

**Deviation Log:** _None_

---

## Phase 1: RAG Corpus Setup

**Status:** 🔴 Not Started  
**Goal:** Stand up the `knowledge_base` table with vector embeddings, build the PubMed ingestion job, and implement the RAG query pattern in FastAPI.  
**Depends on:** Phase 0 (prerequisites verified, `knowledge_base` table and `pgvector` confirmed)  
**Type:** Claude

**Key deliverables:**
- Embedding model selected and documented (OpenAI `text-embedding-3-small` or current best alternative)
- PubMed E-utilities ingestion job: pulls abstracts matching GI/nutrition MeSH terms, inserts with `reviewed: false`
- `knowledge_base` records embedded in batches; failed embeddings retried up to 3 times, then flagged
- RAG query pattern implemented in FastAPI: query embedding → cosine similarity search → inject top-k excerpts into Claude prompt
- RAG trigger threshold defined: which query types retrieve from knowledge base (trend summaries yes, individual meal logging no)

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 2: Food Database Sync

**Status:** 🔴 Not Started  
**Goal:** Implement scheduled sync jobs for Open Food Facts (weekly) and USDA FoodData Central (quarterly) to keep the local food product cache current.  
**Depends on:** Phase 0  
**Type:** Claude

**Key deliverables:**
- Open Food Facts sync job: delta vs full dump decision made and documented; compressed dump processed and upserted into food product cache
- USDA FoodData Central sync job: quarterly JSON export downloaded and reference data updated
- Background job runner selected and configured (Supabase pg_cron + Edge Functions or Celery — decide at phase start based on job complexity)
- `last_checked_at` timestamp tracked per source; alert triggered if a source has not been checked in over 60 days
- Unresolved food lookup gaps logged by restaurant name for manual triage

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 3: Server-Side Update Pipeline

**Status:** 🔴 Not Started  
**Goal:** Make the MCP Server persona, FastAPI system prompt, feature flags, and Claude model version all updatable server-side without a code deployment or app update.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- MCP Server system description moved from hardcode to Supabase `app_config` table; server reads on startup and on configurable refresh interval
- FastAPI system prompt stored in database, refreshable without redeploy
- `feature_flags` table populated and a `/config/features` endpoint serving flags to Flutter app and React dashboard
- `CLAUDE_MODEL` and `CLAUDE_MODEL_FALLBACK` environment variables confirmed in deployment config
- Human review queue logic: unreviewed knowledge base entries surfaced; `notify_affected_users` flag triggers user notifications on significant guideline updates

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 4: Freshness UI & User Notifications

**Status:** 🔴 Not Started  
**Goal:** Surface knowledge freshness information to users and send notifications when significant research updates are incorporated.  
**Depends on:** Phases 1–3  
**Type:** Mixed

**Key deliverables:**
- Settings > About (or Settings > AI Analysis) displays "Food database last updated: [date]" and "Health knowledge base last updated: [date]"
- Significant update notification implemented: in-app banner on next open when a knowledge base entry is approved with `notify_affected_users: true`
- Affected-user lookup: finds users with matching condition in health profile and sends notification
- Minimal internal admin interface built: review queue, approve/reject/edit entries, trigger manual syncs, freshness dashboard
- End-to-end flow tested: PubMed ingestion → human review → approval → user notification

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X — changed X because Y`_

---

## Notes

- **Phase 1 database prerequisites:** The spec (Section 7) explicitly calls for `pgvector`, `knowledge_base`, `feature_flags`, and `health_metrics` tables to be created during Spec 01. Phase 0 will verify whether this was done. If not, migrations must be added before Phase 1 starts.
- **Curation staffing:** The spec requires a human reviewer for knowledge base entries. Define who that person is (the owner, a trusted reviewer, or a well-prompted AI reviewer with human spot-check) at Phase 1 start.
- **RAG without Phase 7 complete:** Phase 1 can build the ingestion pipeline and RAG query infrastructure even if Spec 07 (Food Intelligence) is not complete, but end-to-end insight generation will not work until that spec's correlation engine is in place.
- **Feature flags:** Once the `feature_flags` table is live (Phase 3), new features in all other specs can be gated without app updates. Coordinate with active development specs to take advantage of this early.
