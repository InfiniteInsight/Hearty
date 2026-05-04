# Hearty — Sub-Spec 11: Knowledge Freshness

**Version:** 1.0  
**Date:** 2026-05-04  
**Status:** Future Phase (infrastructure design now; implement progressively)  
**Depends on:** Phase 1 (Supabase), Phase 4 (AI Intelligence / trend engine)

---

## 1. Overview

AI models have a training cutoff. Health and nutrition research evolves continuously — dietary guidance for IBS, GERD, or food intolerances in 2020 may be meaningfully revised by 2025. If Hearty's AI analysis is grounded only in model training data, users with active conditions may receive pattern interpretations based on outdated research.

Knowledge freshness addresses this across three layers:

| Layer | Problem | Solution |
|---|---|---|
| Health knowledge base | Model training data ages | RAG corpus updated from current research |
| Food database | New products, restaurant menus, formulation changes | Scheduled syncs from live data sources |
| App and prompt logic | Analysis approach, AI model version | Server-side configuration, no app update required |

**Guiding constraint:** Freshness infrastructure should not block Phase 1–4 delivery. Design schema and architecture to accommodate it; implement the automation progressively.

---

## 2. Health Knowledge Base (RAG)

### 2.1 Purpose

When Hearty's AI generates trend summaries or explains a pattern ("your acid reflux correlates with late-night meals"), it should be able to ground that explanation in current research rather than relying solely on model weights.

This is a Retrieval-Augmented Generation (RAG) pattern: maintain a curated corpus of health and nutrition research in Supabase; the AI retrieves relevant excerpts at query time and incorporates them into responses.

### 2.2 Corpus Sources

| Source | Content | Access Method | Update Cadence |
|---|---|---|---|
| PubMed abstracts | Nutrition and GI condition research | NCBI E-utilities API (free) | Monthly automated pull |
| NHS dietary guidelines | UK clinical nutrition guidance | Web scrape or RSS | Quarterly or on major revision |
| NIH dietary guidelines (DGA) | US federal dietary guidance | Published PDF / web | Every 5 years with interim updates |
| IBS Network resources | IBS-specific dietary guidance (low-FODMAP, etc.) | Manual curation | When significant updates noted |
| Crohn's & Colitis Foundation | IBD dietary guidance | Manual curation | When significant updates noted |
| EFSA (European Food Safety Authority) | EU food safety and nutrition opinions | Published reports | Quarterly review |

**Scope limit:** The corpus covers dietary patterns, food-symptom relationships, and GI condition management. It does not include general medical literature, drug information, or unrelated health topics.

### 2.3 Supabase Setup

The `pgvector` extension is required. It should be enabled in the Phase 1 Supabase project even if RAG is not implemented until later.

```sql
-- Enable pgvector (Phase 1 action: enable extension, create table shape)
create extension if not exists vector;

create table knowledge_base (
  id uuid primary key default gen_random_uuid(),
  source text not null,               -- 'pubmed', 'nhs', 'nih', 'manual'
  source_id text,                     -- e.g. PubMed PMID, URL
  title text,
  content text not null,              -- abstract or excerpt
  content_embedding vector(1536),     -- OpenAI ada-002 or equivalent
  conditions text[],                  -- e.g. ['ibs', 'gerd', 'celiac']
  tags text[],
  published_at date,
  ingested_at timestamptz default now(),
  reviewed boolean default false,     -- human review flag
  active boolean default true
);

create index knowledge_base_embedding_idx
  on knowledge_base
  using ivfflat (content_embedding vector_cosine_ops);
```

### 2.4 RAG Query Pattern

When generating a trend analysis or summary, the FastAPI layer:
1. Constructs a query from the user's current pattern context (e.g., "acid reflux late-night meals IBS")
2. Embeds the query using the same embedding model used at ingestion
3. Runs a cosine similarity search against `knowledge_base` for the top-k relevant documents
4. Injects retrieved excerpts into the Claude prompt as context
5. Claude generates the analysis grounded in both the user's data and the retrieved research

**Embedding model decision:** Defer to implementation time. Options include OpenAI `text-embedding-3-small` (cost-effective), a self-hosted model via Supabase Edge Functions, or Claude's own embeddings if available. Use a consistent model for ingestion and query.

### 2.5 Curation Process

- **Automated ingestion:** Background job pulls new PubMed abstracts matching condition-specific MeSH terms monthly. Records are inserted with `reviewed: false`.
- **Human review queue:** An admin interface (internal, not user-facing) surfaces unreviewed records. A human reviewer approves, edits, or rejects each before it becomes `active: true`.
- **Major guideline changes:** When a significant update is detected (e.g., a major revision to low-FODMAP guidance), a flag triggers a manual review of all related active records.
- **Source freshness tracking:** Each source has a `last_checked_at` timestamp. The background job alerts if a source has not been checked in over 60 days.

---

## 3. Food Database Freshness

### 3.1 Open Food Facts

Open Food Facts provides weekly data dumps (available at `world.openfoodfacts.org/data`). The dump includes new products and updated nutritional information.

- **Update cadence:** Weekly sync of the delta dump
- **Method:** Background job downloads compressed dump, processes changed/new records, upserts into Hearty's local product cache in Supabase
- **Scope:** Filter to products with valid barcodes and complete nutritional data; skip records with missing key fields

### 3.2 Nutritionix

Nutritionix is a live API — no local sync needed. All restaurant nutrition lookups call the Nutritionix API at query time. The API reflects current menu data. Rate limits and API key rotation are operational concerns, not freshness concerns.

### 3.3 USDA FoodData Central

USDA FoodData Central publishes quarterly data releases. These are authoritative for foundation foods, branded foods, and nutrient profiles.

- **Update cadence:** Quarterly sync after each USDA release
- **Method:** Download FoodData Central JSON export, update the local reference data
- **Priority:** Foundation Foods and SR Legacy data change rarely; Branded Foods update more frequently

### 3.4 Restaurant Menus

Chain restaurant menus change seasonally and are not covered by bulk data sources.

- **Triggered updates:** When a user reports "this item isn't in your database," a queue entry is created for manual or semi-automated lookup
- **Nutritionix coverage:** Most major chains are covered by Nutritionix API directly; local sync is not needed for chains in their database
- **Gap tracking:** Log unresolved food lookups by restaurant name; when a restaurant appears in gaps frequently, prioritize manual ingestion

---

## 4. App and Prompt Updates (Server-Side)

### 4.1 MCP Server Description (Hearty Persona)

The MCP Server's system description — Hearty's persona, tool descriptions, and behavioral instructions — is currently hardcoded in the server.

**Future state:** Store the MCP system description in Supabase (`app_config` table or equivalent). The MCP Server reads it at startup (and on a configurable refresh interval). Updates to Hearty's persona or tool instructions do not require a server redeploy.

### 4.2 REST API System Prompt

The FastAPI system prompt used for external assistant interactions (non-MCP clients) follows the same pattern: stored in the database, read at startup, refreshable without a code deployment.

### 4.3 Claude Model Version

The Claude model identifier (`claude-sonnet-4-6` or successor) is set in an environment variable, not hardcoded in prompt-calling code.

```python
# Current approach — keep this
CLAUDE_MODEL = os.environ.get("CLAUDE_MODEL", "claude-sonnet-4-6")
```

When Anthropic releases a new Claude version, updating the environment variable in the deployment platform (Railway, Render, etc.) and restarting the service is sufficient. No code change or app update required.

**Decision at each model upgrade:** Test the new model against Hearty's prompt suite before switching production. Maintain a `CLAUDE_MODEL_FALLBACK` variable for rollback.

### 4.4 Feature Flags

New analysis features (e.g., a new correlation algorithm, an experimental trend view) can be toggled server-side before they appear in the mobile or web app.

```sql
create table feature_flags (
  key text primary key,
  enabled boolean default false,
  description text,
  enabled_for_users uuid[],  -- null = all users; array = specific users for A/B
  updated_at timestamptz default now()
);
```

The Flutter app and React dashboard read feature flags from a `/config/features` endpoint on app start (cached for the session). Features gated by a flag render only if the flag is enabled.

---

## 5. User-Facing Transparency

### 5.1 Knowledge Last Updated

Settings > About (or Settings > AI Analysis) shows:
- "Food database last updated: [date]"
- "Health knowledge base last updated: [date]"

This is a trust signal. Users with chronic conditions deserve to know how current the underpinning research is.

### 5.2 Significant Update Notifications

When a major guideline change is incorporated that affects a user's tracked conditions, send a notification:

> "New research on IBS and the low-FODMAP diet has been incorporated into Hearty's analysis. Your trend summaries may reflect updated guidance."

**Trigger:** A human reviewer marks a knowledge base addition as `notify_affected_users: true` when approving it. The system finds users with that condition in their health profile and sends the notification.

**Delivery:** In-app notification banner on next open; optionally push notification if user has push enabled. Not an email.

---

## 6. Infrastructure

### 6.1 Background Job System

Scheduled syncs (PubMed monthly, Open Food Facts weekly, USDA quarterly) require a background job runner.

**Options (decide at implementation time):**

| Option | Pros | Cons |
|---|---|---|
| Supabase Edge Functions + pg_cron | No new infrastructure; already on Supabase | Edge Functions have execution time limits; large data dumps may need chunking |
| Celery + Redis (on Railway/Render) | Mature, handles long-running jobs, retry logic | New infrastructure to operate |
| GitHub Actions scheduled workflow | Zero-cost for infrequent syncs; simple | Not ideal for jobs that need DB access at runtime; coupling to GitHub |

**Recommendation (defer to implementation):** Start with Supabase Edge Functions + pg_cron for simplicity. Migrate to Celery only if job complexity or execution time limits become a problem.

### 6.2 Admin Interface

An internal admin interface is needed for:
- Reviewing unreviewed knowledge base entries
- Approving / rejecting / editing entries
- Triggering manual syncs
- Viewing freshness dashboards (last sync per source, queue depth)

**Scope:** This is an internal tool, not user-facing. A minimal React page behind Supabase Auth (admin role) is sufficient. Do not over-engineer at launch.

### 6.3 Embedding Pipeline

At ingestion time, each knowledge base record must be embedded. This is a blocking call to an embedding API (OpenAI or equivalent).

**Design:** The ingestion job processes records in batches. Failed embeddings are retried up to 3 times before the record is marked `embedding_failed: true` for manual review. Records without embeddings are not surfaced in RAG queries.

---

## 7. Phase 1 Actions (Do Now, Not Later)

The following should be done during Phase 1 to avoid schema migrations when this phase is implemented:

| Action | Where |
|---|---|
| Enable `pgvector` extension in Supabase | Supabase dashboard or migration |
| Create `knowledge_base` table (empty) | Phase 1 DB migration |
| Create `health_metrics` table (empty, for Health Connect) | Phase 1 DB migration |
| Create `feature_flags` table (empty) | Phase 1 DB migration |
| Set `CLAUDE_MODEL` as an environment variable | Deployment config |

---

## 8. Key Open Decisions for This Phase

1. **Embedding model selection** — OpenAI `text-embedding-3-small` vs alternatives; must match ingestion and query
2. **Background job system** — Supabase pg_cron + Edge Functions vs Celery; decide based on job complexity at implementation time
3. **Curation staffing** — who reviews knowledge base additions? Define a lightweight process (the owner, a trusted reviewer, or a well-prompted AI reviewer with human spot-check)
4. **RAG trigger threshold** — not every AI query needs RAG; define which query types retrieve from knowledge base (trend summaries yes; individual meal logging no)
5. **Open Food Facts delta sync vs full dump** — the delta API is simpler but requires tracking change IDs; full weekly dump is reliable but large; evaluate at implementation
