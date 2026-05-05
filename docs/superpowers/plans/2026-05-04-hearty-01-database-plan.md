# Hearty — Database (Spec 01) — Living Plan

**Spec:** [`hearty-01-database.md`](../specs/2026-05-04-hearty-01-database.md)  
**Roadmap Phase:** Phase 1 — Foundation  
**Plan Status:** 🟢 Completed  
**Last Updated:** 2026-05-04 (Phase 0 completed)  
**Last Verified Against Spec:** 2026-05-04 — re-verify if spec has changed since  
**Open Deviations:** 0

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
| 0 | Review & Align | 🟢 Completed | — | Claude (start of every session) |
| 1 | Supabase Project Setup | 🟢 Completed | — | Manual (browser) |
| 2 | Schema Deployment | 🟢 Completed | Phase 1 | Claude |
| 3 | Auth Configuration | 🟢 Completed | Phase 1 | Manual (browser) |
| 4 | Storage Bucket | 🟢 Completed | Phase 1 | Manual (browser) |
| 5 | Smoke Test | 🟢 Completed | Phases 2–4 | Claude |

---

## Phase 0: Review & Align

**Status:** 🟢 Completed  
**Goal:** Verify the dev environment, confirm the spec hasn't drifted from this plan, and identify exactly which phase to start or resume.  
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty database setup.
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

Working directory: /home/evan/projects/food-journal-assistant

Steps:
1. Read both files in full:
   - docs/superpowers/plans/2026-05-04-hearty-01-database-plan.md
   - docs/superpowers/specs/2026-05-04-hearty-01-database.md

2. Check the dev environment (run each command):
   - git status
   - node --version  (need >= 18)
   - npm --version
   - supabase --version  (if not found, note it — Phase 2 will install it)
   - ls .env 2>/dev/null && echo "exists" || echo "missing"

3. Spec drift check — the plan was written on 2026-05-04. Scan the spec for
   any changes to: table definitions, indexes, RLS policies, auth setup.
   If you find anything that conflicts with the plan's task steps, list it.

4. Report:
   - Environment: what is/isn't installed
   - Spec alignment: any drift found, or "clean"
   - Next action: which phase to proceed with (or what to fix first)

Before running any command, verify it exists with --help or equivalent.
If a command doesn't behave as expected, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
```

**Deviation Log:** _None_

---

## Phase 1: Supabase Project Setup

**Status:** 🔴 Not Started  
**Goal:** Create the Supabase project and capture the three credentials needed by every downstream component.  
**Type:** Manual — done in the browser, no Claude session needed.

- [ ] Go to [supabase.com](https://supabase.com) → **New Project**
  - Name: `hearty`
  - Region: closest to you
  - Database password: generate a strong one and **save it separately** — you'll need it for CLI commands

- [ ] Wait for the project to provision (~2 min), then go to **Settings → API** and copy:
  - **Project URL** — e.g. `https://abcxyz.supabase.co`
  - **anon / public** key
  - **service_role / secret** key ← keep this private, never commit it

- [ ] Create `/home/evan/projects/food-journal-assistant/.env`:
  ```
  SUPABASE_URL=https://abcxyz.supabase.co
  SUPABASE_ANON_KEY=eyJ...
  SUPABASE_SERVICE_ROLE_KEY=eyJ...
  ```

- [ ] Verify `.env` is in `.gitignore`. If not:
  ```bash
  echo ".env" >> .gitignore && git add .gitignore && git commit -m "chore: ignore .env"
  ```

**Complete when:** `.env` exists with all three values populated.

**Deviation Log:** _None_

---

## Phase 2: Schema Deployment

**Status:** 🟢 Completed  
**Goal:** Install Supabase CLI, link to the project, deploy the initial migration, verify all 8 tables.  
**Depends on:** Phase 1 complete

### Activation Prompt

```
You are implementing Phase 2 (Schema Deployment) of the Hearty database setup.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Supabase project exists; credentials are in .env
- Spec: docs/superpowers/specs/2026-05-04-hearty-01-database.md
- Plan: docs/superpowers/plans/2026-05-04-hearty-01-database-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Task 2.1 and Task 2.2 in order.
When both tasks are done:
- Mark Phase 2 status as 🟢 Completed in the plan file
- Commit all new files
- Tell me to run /compact
- Remind me that Phase 3 is manual (browser steps) and its checklist is in the plan
```

---

### Task 2.1: Install Supabase CLI and initialize project

**Status:** 🟢 Completed

- [ ] Check if CLI is already installed: `supabase --version`
  If found, skip the install step.

- [ ] If not installed (WSL/Linux):
  ```bash
  npm install -g supabase
  supabase --version  # verify
  ```

- [ ] Initialize Supabase project structure:
  ```bash
  supabase init
  ```
  Creates `supabase/config.toml`. Expected: `Finished supabase init.`

- [ ] Find your project ref from the Supabase URL in `.env`:
  `https://abcxyz.supabase.co` → ref is `abcxyz`

- [ ] Link CLI to the project:
  ```bash
  supabase link --project-ref <your-project-ref>
  ```
  Enter the database password from Phase 1 when prompted.  
  Expected: `Finished supabase link.`

**Deviation Log:** _None_

---

### Task 2.2: Create and deploy the initial migration

**Status:** 🟢 Completed

- [ ] Create the migrations directory:
  ```bash
  mkdir -p supabase/migrations
  ```

- [ ] Create `supabase/migrations/20260504000001_initial_schema.sql`  
  Copy the SQL verbatim from Section 8 of `hearty-01-database.md` (the full block under "Full Migration File (Initial)").

- [ ] Deploy:
  ```bash
  supabase db push
  ```
  Expected: `Finished supabase db push.`

- [ ] Verify 8 tables exist:
  ```bash
  supabase db execute --sql "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"
  ```
  Expected — exactly these tables: `food_log_photos`, `food_triggers`, `health_profile`, `meals`, `notification_preferences`, `offline_queue`, `symptoms`, `wellbeing_snapshots`

- [ ] Verify RLS is enabled on all 8 tables:
  ```bash
  supabase db execute --sql "SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;"
  ```
  Expected: all 8 show `rowsecurity | t`

- [ ] Verify indexes:
  ```bash
  supabase db execute --sql "SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND indexname LIKE 'idx_%' ORDER BY indexname;"
  ```
  Expected: 11 `idx_*` entries matching the spec

- [ ] Commit:
  ```bash
  git add supabase/
  git commit -m "feat: add initial Supabase schema migration"
  ```

**Deviation Log:** _None_

---

## Phase 3: Auth Configuration

**Status:** 🔴 Not Started  
**Goal:** Enable Google OAuth (Android) and Magic Link (web) in Supabase Dashboard.  
**Type:** Manual — browser steps only, no Claude session needed.  
**Note:** The Android SHA-1 fingerprint step requires a debug keystore that may not exist yet. Skip that sub-step and return to it at the start of Spec 04.

### Task 3.1: Enable Google OAuth

- [ ] Supabase Dashboard → **Authentication → Providers → Google** → Enable

- [ ] [Google Cloud Console](https://console.cloud.google.com) → **APIs & Services → Credentials → Create OAuth client ID**
  - Type: **Android**
  - Package name: `com.hearty.app`
  - SHA-1 fingerprint (skip if keystore doesn't exist yet):
    ```bash
    keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android 2>/dev/null | grep "SHA1:"
    ```

- [ ] Copy the **OAuth Client ID** → paste into Supabase Google provider → **Authorized Client IDs** → Save

**Deviation Log:** Supabase dashboard navigation changed — Google provider is now under **Sign In / Providers**, not Authentication → Providers. SHA-1 deferred (placeholder `00:00:00...` used); real fingerprint to be added in Spec 04.

---

### Task 3.2: Enable Magic Link (web)

- [ ] Supabase Dashboard → **Authentication → Providers → Email**
  - Enable Magic links
  - Disable password sign-in

- [ ] **Authentication → URL Configuration**
  - Site URL: `http://localhost:5173`
  - Redirect URLs: add `http://localhost:5173/**`

**Phase 3 complete when:** Both providers show as Enabled in the Supabase Dashboard.

**Deviation Log:** "Disable password sign-in" toggle does not exist in current Supabase dashboard UI. Magic links are on by default. Password-only enforcement will be handled at the app level in Spec 03 by never calling `signInWithPassword()`. URL configuration confirmed done via Sign In / URL Configuration (navigation differs from plan).

---

## Phase 4: Storage Bucket

**Status:** 🔴 Not Started  
**Goal:** Create the `food-photos` storage bucket with user-scoped RLS.  
**Depends on:** Phase 1 complete  
**Note:** Food photo upload is a Phase 4 roadmap feature (Spec 06). Create the bucket now so Specs 02 and 03 can reference a real URL. Defer if you prefer — return at the start of Spec 06.

### Activation Prompt

```
You are implementing Phase 4 (Storage Bucket) of the Hearty database setup.

Working directory: /home/evan/projects/food-journal-assistant

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Tasks:
1. Create supabase/migrations/20260504000002_storage_bucket.sql with:

   INSERT INTO storage.buckets (id, name, public)
   VALUES ('food-photos', 'food-photos', false)
   ON CONFLICT (id) DO NOTHING;

   CREATE POLICY "food_photos_insert" ON storage.objects
     FOR INSERT WITH CHECK (
       bucket_id = 'food-photos'
       AND (storage.foldername(name))[1] = auth.uid()::text
     );

   CREATE POLICY "food_photos_select" ON storage.objects
     FOR SELECT USING (
       bucket_id = 'food-photos'
       AND (storage.foldername(name))[1] = auth.uid()::text
     );

   CREATE POLICY "food_photos_delete" ON storage.objects
     FOR DELETE USING (
       bucket_id = 'food-photos'
       AND (storage.foldername(name))[1] = auth.uid()::text
     );

2. Deploy: supabase db push
3. Verify the bucket appears in Supabase Dashboard → Storage
4. Commit:
   git add supabase/migrations/20260504000002_storage_bucket.sql
   git commit -m "feat: add food-photos storage bucket with RLS"
5. Mark Phase 4 as 🟢 Completed in the plan file
6. Tell me to run /compact; remind me Phase 5 (Smoke Test) is next
```

**Deviation Log:** _None_

---

## Phase 5: Smoke Test

**Status:** 🔴 Not Started  
**Goal:** Verify the schema works end-to-end — service role can write, RLS blocks cross-user reads, JSONB round-trips correctly.  
**Depends on:** Phases 2–4 complete

### Activation Prompt

```
You are running Phase 5 (Smoke Test) for the Hearty database setup.

Working directory: /home/evan/projects/food-journal-assistant

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Run these four checks (use the Supabase Dashboard SQL editor or supabase db execute):

CHECK 1 — Service role write:
  INSERT INTO meals (user_id, description, input_method)
  VALUES ('00000000-0000-0000-0000-000000000001', 'smoke test meal', 'text');
  Expected: 1 row inserted

CHECK 2 — RLS isolation (as a different user UUID, using the anon key):
  SELECT * FROM meals WHERE user_id = '00000000-0000-0000-0000-000000000001';
  Expected: 0 rows (RLS blocks cross-user read)

CHECK 3 — Cleanup:
  DELETE FROM meals WHERE description = 'smoke test meal';

CHECK 4 — JSONB round-trip:
  INSERT INTO meals (user_id, description, foods, input_method)
  VALUES (
    '00000000-0000-0000-0000-000000000001',
    'jsonb test',
    '[{"name":"grilled salmon","data_source":"ai_estimate","confidence":0.8}]'::jsonb,
    'text'
  );
  SELECT foods->0->>'name' FROM meals WHERE description = 'jsonb test';
  Expected: "grilled salmon"
  Cleanup: DELETE FROM meals WHERE description = 'jsonb test';

If all 4 pass:
- Mark Phase 5 as 🟢 Completed in the plan file
- Mark Plan Status as 🟢 Completed in the plan header
- Commit: git add docs/superpowers/plans/ && git commit -m "docs: database plan complete"
- Tell me this spec is done and Spec 02 (MCP Server) is next
```

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X, Task Y — changed X because Y`_

[2026-05-04] — Phase 2, Task 2.1 — used `npx supabase` instead of global install (npm global prefix requires sudo on this machine)
[2026-05-04] — Phase 2, Task 2.2 — migration filename is `20260504223232_initial_schema.sql` (CLI-generated timestamp) instead of the hardcoded `20260504000001_initial_schema.sql` in the plan; supabase skill requires using `supabase migration new` rather than inventing filenames

---

## Notes

- **`food_cache` table** (referenced in Spec 07 as living in Spec 01): will be added as a migration in the Spec 07 Food Intelligence plan when Phase 4 roadmap work begins.
- **Android SHA-1 fingerprint** (Phase 3, Task 3.1): defer to Spec 04 plan if the Android debug keystore doesn't exist yet.
