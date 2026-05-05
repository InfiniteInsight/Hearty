# Hearty — MCP Server (Spec 02) — Living Plan

**Spec:** [`hearty-02-mcp-server.md`](../specs/2026-05-04-hearty-02-mcp-server.md)
**Roadmap Phase:** Phase 1 — Foundation
**Plan Status:** 🟢 Completed
**Last Updated:** 2026-05-05
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
| 1 | Project Scaffold | 🟢 Completed | Spec 01 plan 🟢 | Claude |
| 2 | Supabase Client & Health Profile Context | 🟢 Completed | Phase 1 | Claude |
| 3 | Logging Tools (log_meal, log_symptoms, log_wellbeing) | 🟢 Completed | Phase 2 | Claude |
| 4 | Query Tools (query_history, get_trends, get_summary) | 🟢 Completed | Phase 2 | Claude |
| 5 | Server Entrypoint & Hearty Persona | 🟢 Completed | Phases 3–4 | Claude |
| 6 | Integration Test | 🟢 Completed | Phase 5 | Claude |

---

## Phase 0: Review & Align

**Status:** 🟢 Completed
**Goal:** Verify the dev environment, confirm Spec 01 is complete, confirm the spec hasn't drifted from this plan, and identify exactly which phase to start or resume.
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty MCP Server setup.
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

Working directory: /home/evan/projects/food-journal-assistant

Steps:

1. Read both plan files in full:
   - docs/superpowers/plans/2026-05-04-hearty-01-database-plan.md
   - docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md

   Confirm that the Spec 01 (database) plan shows Plan Status: 🟢 Completed
   in its header. If it does not, stop here and tell me — Spec 02 depends
   on the database schema existing.

2. Read the spec in full:
   - docs/superpowers/specs/2026-05-04-hearty-02-mcp-server.md

3. Check the dev environment (run each command):
   - git status
   - node --version   (spec requires Node.js 20+)
   - npm --version
   - ls hearty-mcp 2>/dev/null && echo "exists" || echo "not created yet"
   - npm info @modelcontextprotocol/sdk version   (capture the current latest version)
   - npm info @supabase/supabase-js version        (capture the current latest version)

4. Spec drift check — this plan was written on 2026-05-04. Scan the spec for
   any changes to: tool names, input schemas, file structure, auth approach,
   system prompt, error handling pattern, or package.json dependencies.
   If you find anything that conflicts with the plan's task steps, list it.

5. Report:
   - Spec 01 plan status: complete or not
   - Environment: Node version (pass/fail), npm version, hearty-mcp directory exists or not
   - Current @modelcontextprotocol/sdk version (flag if different from "^1.0.0" in spec)
   - Current @supabase/supabase-js version (flag if different from "^2.0.0" in spec)
   - Spec alignment: any drift found, or "clean"
   - Next action: which phase to proceed with (or what to fix first)

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
Commit: git add docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md && git commit -m "docs: phase 0 complete — mcp server plan aligned"
Tell me to run /compact, then use the Phase 1 Activation Prompt in this plan.
```

**Deviation Log:** _None_

---

## Phase 1: Project Scaffold

**Status:** 🟢 Completed
**Goal:** Create the `hearty-mcp/` subdirectory, initialize the npm project, install all dependencies, and lay down the full directory skeleton from spec §2.
**Depends on:** Spec 01 plan marked 🟢 Completed

### Activation Prompt

```
You are implementing Phase 1 (Project Scaffold) of the Hearty MCP Server setup.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-02-mcp-server.md
- Plan: docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Task 1.1 and Task 1.2 in order.
When both tasks are done:
- Mark Phase 1 status as 🟢 Completed in the plan file
- Commit all new files
- Tell me to run /compact
- Remind me that the Phase 2 Activation Prompt is at the top of Phase 2 in this plan file
```

---

### Task 1.1: Initialize npm project and install dependencies

**Status:** 🟢 Completed

- [ ] Create and enter the project directory:
  ```bash
  mkdir -p /home/evan/projects/food-journal-assistant/hearty-mcp
  ```

- [ ] Initialize npm (accept defaults; `type: module` will be set manually):
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npm init -y
  ```
  Expected: `package.json` created with name `hearty-mcp`

- [ ] Write `package.json` matching spec §10 exactly:
  ```json
  {
    "name": "hearty-mcp",
    "version": "1.0.0",
    "type": "module",
    "scripts": {
      "build": "tsc",
      "start": "node dist/index.js",
      "dev": "tsx src/index.ts"
    },
    "dependencies": {
      "@modelcontextprotocol/sdk": "^1.0.0",
      "@supabase/supabase-js": "^2.0.0"
    },
    "devDependencies": {
      "typescript": "^5.0.0",
      "tsx": "^4.0.0",
      "@types/node": "^20.0.0"
    }
  }
  ```
  If Phase 0 found that the current SDK or supabase-js version has a different major, update the semver range here and log the deviation.

- [ ] Install all dependencies:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npm install
  ```
  Expected: `node_modules/` created, no peer-dep errors.

- [ ] Verify key packages are resolvable:
  ```bash
  ls /home/evan/projects/food-journal-assistant/hearty-mcp/node_modules/@modelcontextprotocol/sdk
  ls /home/evan/projects/food-journal-assistant/hearty-mcp/node_modules/@supabase/supabase-js
  ```
  Expected: both directories exist.

**Deviation Log:** _None_

---

### Task 1.2: Create directory structure, tsconfig, and .env.example

**Status:** 🟢 Completed

- [ ] Create the directory skeleton from spec §2:
  ```bash
  mkdir -p /home/evan/projects/food-journal-assistant/hearty-mcp/src/tools
  ```

- [ ] Create `tsconfig.json` at `hearty-mcp/tsconfig.json` matching spec §11 exactly:
  ```json
  {
    "compilerOptions": {
      "target": "ES2022",
      "module": "NodeNext",
      "moduleResolution": "NodeNext",
      "outDir": "dist",
      "rootDir": "src",
      "strict": true,
      "esModuleInterop": true,
      "skipLibCheck": true
    },
    "include": ["src/**/*"]
  }
  ```

- [ ] Create `hearty-mcp/.env.example` matching spec §6.1 exactly:
  ```
  SUPABASE_URL=https://your-project.supabase.co
  SUPABASE_SERVICE_KEY=eyJhbGci...         # service_role key for personal use
  HEARTY_USER_ID=uuid-of-the-owner         # single-user mode: always act as this user
  ```

- [ ] Create empty placeholder source files so the directory tree matches spec §2:
  ```bash
  touch /home/evan/projects/food-journal-assistant/hearty-mcp/src/index.ts
  touch /home/evan/projects/food-journal-assistant/hearty-mcp/src/supabase.ts
  touch /home/evan/projects/food-journal-assistant/hearty-mcp/src/context.ts
  touch /home/evan/projects/food-journal-assistant/hearty-mcp/src/tools/log-meal.ts
  touch /home/evan/projects/food-journal-assistant/hearty-mcp/src/tools/log-symptoms.ts
  touch /home/evan/projects/food-journal-assistant/hearty-mcp/src/tools/log-wellbeing.ts
  touch /home/evan/projects/food-journal-assistant/hearty-mcp/src/tools/query-history.ts
  touch /home/evan/projects/food-journal-assistant/hearty-mcp/src/tools/get-trends.ts
  touch /home/evan/projects/food-journal-assistant/hearty-mcp/src/tools/get-summary.ts
  ```

- [ ] Verify directory tree:
  ```bash
  find /home/evan/projects/food-journal-assistant/hearty-mcp/src -type f | sort
  ```
  Expected — exactly these 9 files:
  ```
  hearty-mcp/src/context.ts
  hearty-mcp/src/index.ts
  hearty-mcp/src/supabase.ts
  hearty-mcp/src/tools/get-summary.ts
  hearty-mcp/src/tools/get-trends.ts
  hearty-mcp/src/tools/log-meal.ts
  hearty-mcp/src/tools/log-symptoms.ts
  hearty-mcp/src/tools/log-wellbeing.ts
  hearty-mcp/src/tools/query-history.ts
  ```

- [ ] Verify `.gitignore` at the repo root includes `node_modules` and `.env`.
  If not, add both:
  ```bash
  grep -q "node_modules" /home/evan/projects/food-journal-assistant/.gitignore || echo "node_modules" >> /home/evan/projects/food-journal-assistant/.gitignore
  grep -q "^\.env$" /home/evan/projects/food-journal-assistant/.gitignore || echo ".env" >> /home/evan/projects/food-journal-assistant/.gitignore
  ```

- [ ] Commit:
  ```bash
  git -C /home/evan/projects/food-journal-assistant add hearty-mcp/package.json hearty-mcp/package-lock.json hearty-mcp/tsconfig.json hearty-mcp/.env.example hearty-mcp/src/ .gitignore
  git -C /home/evan/projects/food-journal-assistant commit -m "feat: scaffold hearty-mcp project structure"
  ```

**Deviation Log:** _None_

---

## Phase 2: Supabase Client & Health Profile Context

**Status:** 🟢 Completed
**Goal:** Implement `src/supabase.ts` (Supabase client + `getUserId()`) and `src/context.ts` (`getHealthProfileContext()`). These two modules are shared by all tool handlers.
**Depends on:** Phase 1 complete

### Activation Prompt

```
You are implementing Phase 2 (Supabase Client & Health Profile Context) of the
Hearty MCP Server setup.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-02-mcp-server.md
- Plan: docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md
- Source files to implement: hearty-mcp/src/supabase.ts, hearty-mcp/src/context.ts

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Task 2.1 and Task 2.2 in order.
When both tasks are done:
- Mark Phase 2 status as 🟢 Completed in the plan file
- Commit all changed files
- Tell me to run /compact
- Remind me that the Phase 3 Activation Prompt is at the top of Phase 3 in this plan file
```

---

### Task 2.1: Implement src/supabase.ts

**Status:** 🟢 Completed

Implement `hearty-mcp/src/supabase.ts` from spec §6.2 exactly:

```typescript
// src/supabase.ts

import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL!;
const supabaseKey = process.env.SUPABASE_SERVICE_KEY!;

if (!supabaseUrl || !supabaseKey) {
  throw new Error('SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in environment.');
}

export const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

export function getUserId(): string {
  const userId = process.env.HEARTY_USER_ID;
  if (!userId) throw new Error('HEARTY_USER_ID must be set.');
  return userId;
}
```

- [ ] Write the file at `hearty-mcp/src/supabase.ts`
- [ ] TypeScript compile-check (should produce no errors, though `dist/` output is not yet needed):
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsc --noEmit 2>&1 | head -30
  ```
  At this stage, errors in other `.ts` files (empty stubs) are acceptable. Errors inside `supabase.ts` itself are not — fix before moving on.

**Deviation Log:** _None_

---

### Task 2.2: Implement src/context.ts

**Status:** 🟢 Completed

Implement `hearty-mcp/src/context.ts` from spec §4.2 exactly:

```typescript
// src/context.ts

import { supabase } from './supabase.js';

export interface HealthProfile {
  allergens: string[];           // e.g. ["peanuts", "shellfish"]
  intolerances: string[];        // e.g. ["lactose", "gluten"]
  conditions: string[];          // e.g. ["IBS-D", "GERD", "Crohn's"]
  dietary_protocols: string[];   // e.g. ["low-FODMAP", "AIP", "gluten-free"]
  notes: string | null;          // free-form context the user has added
}

export async function getHealthProfileContext(userId: string): Promise<string> {
  const { data, error } = await supabase
    .from('health_profile')
    .select('*')
    .eq('user_id', userId)
    .single();

  if (error || !data) return '';

  const profile: HealthProfile = data;
  const parts: string[] = [];

  if (profile.allergens?.length) {
    parts.push(`Known allergens: ${profile.allergens.join(', ')}.`);
  }
  if (profile.intolerances?.length) {
    parts.push(`Food intolerances: ${profile.intolerances.join(', ')}.`);
  }
  if (profile.conditions?.length) {
    parts.push(`Medical conditions: ${profile.conditions.join(', ')}.`);
  }
  if (profile.dietary_protocols?.length) {
    parts.push(`Dietary protocols: ${profile.dietary_protocols.join(', ')}.`);
  }
  if (profile.notes) {
    parts.push(`Additional context: ${profile.notes}`);
  }

  if (!parts.length) return '';

  return `\n\n[USER HEALTH PROFILE — use this context silently to enrich responses]\n${parts.join(' ')}\n`;
}
```

- [ ] Write the file at `hearty-mcp/src/context.ts`
- [ ] TypeScript compile-check:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsc --noEmit 2>&1 | head -30
  ```
  Errors inside `context.ts` or `supabase.ts` must be zero before moving on.

- [ ] Commit:
  ```bash
  git -C /home/evan/projects/food-journal-assistant add hearty-mcp/src/supabase.ts hearty-mcp/src/context.ts
  git -C /home/evan/projects/food-journal-assistant commit -m "feat: add supabase client and health profile context"
  ```

**Deviation Log:** _None_

---

## Phase 3: Logging Tools

**Status:** 🟢 Completed
**Goal:** Implement the three logging tool handlers: `log_meal`, `log_symptoms`, `log_wellbeing`. Each exports a `register*()` function that accepts `McpServer` and registers the tool via `server.tool()`.
**Depends on:** Phase 2 complete

**Note on SDK API:** Before writing any handler, verify the current `server.tool()` signature against the installed SDK:
```bash
cat /home/evan/projects/food-journal-assistant/hearty-mcp/node_modules/@modelcontextprotocol/sdk/README.md | head -100
```
The spec shows `server.tool(name, description, schema, handler)`. If the installed SDK has a different signature, stop and tell the user — do not adapt silently.

**SDK CHECK DONE (2026-05-04):** server.tool() is deprecated; all handlers use server.registerTool(name, { description, inputSchema: ZodRawShape }, handler) + import { z } from 'zod'. Approved by user.

**Error handling pattern:** Every tool handler (spec §7) must wrap its logic in:
```typescript
try {
  // ... tool logic
} catch (err) {
  const message = err instanceof Error ? err.message : 'Unknown error';
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify({
          success: false,
          error: message,
          hint: 'Check SUPABASE_URL, SUPABASE_SERVICE_KEY, and HEARTY_USER_ID in your MCP env config.'
        })
      }
    ],
    isError: true
  };
}
```

**Health profile injection pattern:** Every tool handler (spec §4.3) must append context:
```typescript
const context = await getHealthProfileContext(userId);
return {
  content: [
    { type: 'text', text: JSON.stringify(result) },
    ...(context ? [{ type: 'text', text: context }] : [])
  ]
};
```

### Activation Prompt

```
You are implementing Phase 3 (Logging Tools) of the Hearty MCP Server setup.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-02-mcp-server.md  (sections 5.1, 5.2, 5.3, 7)
- Plan: docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md
- Source files to implement:
    hearty-mcp/src/tools/log-meal.ts
    hearty-mcp/src/tools/log-symptoms.ts
    hearty-mcp/src/tools/log-wellbeing.ts

IMPORTANT — before writing any handler:
Check the installed SDK's actual API surface:
  cat /home/evan/projects/food-journal-assistant/hearty-mcp/node_modules/@modelcontextprotocol/sdk/README.md | head -150
If server.tool() has a different signature than spec §9 describes, stop and tell me — do not adapt silently.

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 3.1, 3.2, and 3.3 in order.
When all three tasks are done:
- Mark Phase 3 status as 🟢 Completed in the plan file
- Commit all changed files
- Tell me to run /compact
- Remind me that the Phase 4 Activation Prompt is at the top of Phase 4 in this plan file
```

---

### Task 3.1: Implement src/tools/log-meal.ts

**Status:** 🟢 Completed

Implement `hearty-mcp/src/tools/log-meal.ts`. The tool name, description, `inputSchema`, and handler behavior must match spec §5.1 exactly.

Function signature:
```typescript
export function registerLogMeal(server: McpServer): void
```

Handler behavior (spec §5.1):
1. Call `getUserId()` from `../supabase.js` to get `userId`
2. Insert a row into the `meals` table; capture returned `id`
3. Call `getHealthProfileContext(userId)` from `../context.js`
4. Return: `{ success: true, meal_id: <id>, summary: "<description>" }` plus health profile context block
5. Wrap all logic in the standard try/catch pattern (spec §7)

Required `inputSchema` properties (from spec §5.1):
- `description` (string, **required**)
- `meal_type` (string enum: breakfast, lunch, dinner, snack, drink, supplement, other)
- `foods` (array of objects — see spec §5.1 for full nested schema)
- `location` (string)
- `mood_before` (number)
- `hunger_before` (number)
- `logged_at` (string, ISO 8601; default to `new Date().toISOString()` if not provided)
- `input_method` (string enum: voice, text, photo, barcode; default `"text"`)
- `offline_id` (string)
- `notes` (string)

- [ ] Write the file at `hearty-mcp/src/tools/log-meal.ts`
- [ ] TypeScript compile-check:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsc --noEmit 2>&1 | head -40
  ```
  No errors in `log-meal.ts` before moving on.

**Deviation Log:** _None_

---

### Task 3.2: Implement src/tools/log-symptoms.ts

**Status:** 🟢 Completed

Implement `hearty-mcp/src/tools/log-symptoms.ts`. The tool name, description, `inputSchema`, and handler behavior must match spec §5.2 exactly.

Function signature:
```typescript
export function registerLogSymptoms(server: McpServer): void
```

Handler behavior (spec §5.2):
1. Call `getUserId()` to get `userId`
2. Insert **each symptom** in the `symptoms` array as a **separate row** in the `symptoms` table, all sharing the same `meal_id` and `onset_minutes`
3. After inserting, query `food_triggers` for any trigger matching the symptom types logged — include in the response if patterns exist
4. Call `getHealthProfileContext(userId)`
5. Return: `{ success: true, inserted: <count>, trigger_warnings: [...] }` plus health profile context block
6. Wrap all logic in the standard try/catch pattern (spec §7)

Required `inputSchema` properties (from spec §5.2):
- `symptoms` (array of objects, **required**) — each with:
  - `symptom_type` (string enum — 15 values, see spec §5.2)
  - `severity` (number)
  - `duration_minutes` (number)
  - `bathroom_urgency` (number, 0–5)
  - `bathroom_visits` (number)
  - `stool_consistency` (number, Bristol 1–7)
- `meal_id` (string, UUID)
- `onset_minutes` (number)
- `raw_description` (string)
- `notes` (string)
- `logged_at` (string, ISO 8601; default to `new Date().toISOString()`)

- [ ] Write the file at `hearty-mcp/src/tools/log-symptoms.ts`
- [ ] TypeScript compile-check:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsc --noEmit 2>&1 | head -40
  ```
  No errors in `log-symptoms.ts` before moving on.

**Deviation Log:** _None_

---

### Task 3.3: Implement src/tools/log-wellbeing.ts

**Status:** 🟢 Completed

Implement `hearty-mcp/src/tools/log-wellbeing.ts`. The tool name, description, `inputSchema`, and handler behavior must match spec §5.3 exactly.

Function signature:
```typescript
export function registerLogWellbeing(server: McpServer): void
```

Handler behavior (spec §5.3):
1. Call `getUserId()` to get `userId`
2. Insert a row into `wellbeing_snapshots` table
3. Call `getHealthProfileContext(userId)`
4. Return: `{ success: true, snapshot_id: <id> }` plus health profile context block
5. Wrap all logic in the standard try/catch pattern (spec §7)

`inputSchema` properties (all optional — from spec §5.3):
- `energy_level` (number, 1–10)
- `mood` (number, 1–10)
- `stress_level` (number, 1–10)
- `sleep_hours` (number)
- `sleep_quality` (number, 1–10)
- `hydration` (number, 1–10)
- `exercise_minutes` (number)
- `notes` (string)
- `logged_at` (string, ISO 8601; default to `new Date().toISOString()`)

- [ ] Write the file at `hearty-mcp/src/tools/log-wellbeing.ts`
- [ ] TypeScript compile-check:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsc --noEmit 2>&1 | head -40
  ```
  No errors in `log-wellbeing.ts` before moving on.

- [ ] Commit all three tool files:
  ```bash
  git -C /home/evan/projects/food-journal-assistant add hearty-mcp/src/tools/log-meal.ts hearty-mcp/src/tools/log-symptoms.ts hearty-mcp/src/tools/log-wellbeing.ts
  git -C /home/evan/projects/food-journal-assistant commit -m "feat: implement log_meal, log_symptoms, log_wellbeing tools"
  ```

**Deviation Log:** _None_

---

## Phase 4: Query Tools

**Status:** 🟢 Completed
**Goal:** Implement the three query tool handlers: `query_history`, `get_trends`, `get_summary`.
**Depends on:** Phase 2 complete

**Deferred:** `get_trends` calls `run_trend_analysis(user_id)` as a Supabase RPC (spec §5.5). That RPC is not defined until Spec 07 (Food Intelligence). For this phase, if `food_triggers` is empty or stale, return `{ triggers: [], note: "Trend analysis not yet available — will activate once food intelligence (Spec 07) is deployed." }` instead of calling the RPC. See Deviation Log entry below.

### Activation Prompt

```
You are implementing Phase 4 (Query Tools) of the Hearty MCP Server setup.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-02-mcp-server.md  (sections 5.4, 5.5, 5.6, 7)
- Plan: docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md
- Source files to implement:
    hearty-mcp/src/tools/query-history.ts
    hearty-mcp/src/tools/get-trends.ts
    hearty-mcp/src/tools/get-summary.ts

IMPORTANT — before writing any handler:
Check the installed SDK's actual API surface if you haven't already:
  cat /home/evan/projects/food-journal-assistant/hearty-mcp/node_modules/@modelcontextprotocol/sdk/README.md | head -150
If server.tool() has a different signature than spec §9 describes, stop and tell me — do not adapt silently.

DEFERRED: get_trends — the Supabase RPC run_trend_analysis(user_id) is not available
until Spec 07. If food_triggers is empty or its last_updated is > 24h ago, return:
  { triggers: [], note: "Trend analysis not yet available — will activate once food intelligence (Spec 07) is deployed." }
Do NOT attempt to call the RPC.

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 4.1, 4.2, and 4.3 in order.
When all three tasks are done:
- Mark Phase 4 status as 🟢 Completed in the plan file
- Commit all changed files
- Tell me to run /compact
- Remind me that the Phase 5 Activation Prompt is at the top of Phase 5 in this plan file
```

---

### Task 4.1: Implement src/tools/query-history.ts

**Status:** 🟢 Completed

Implement `hearty-mcp/src/tools/query-history.ts`. The tool name, description, `inputSchema`, and handler behavior must match spec §5.4 exactly.

Function signature:
```typescript
export function registerQueryHistory(server: McpServer): void
```

Handler behavior (spec §5.4):
1. Call `getUserId()` to get `userId`
2. Build a Supabase query joining `meals` with `symptoms` on `meal_id`, filtered by `user_id`
3. Apply `start_date` / `end_date` filters (default: 7 days ago to now)
4. Apply `symptom_type` filter if provided (match on `symptoms.symptom_type`)
5. Apply `food_keyword` as case-insensitive ILIKE on `meals.description` and JSONB `meals.foods`
6. Return up to `limit` records (default 20), with symptoms nested under each meal
7. No health profile injection needed (read-only query tool)
8. Wrap all logic in the standard try/catch pattern (spec §7)

`inputSchema` properties (all optional — from spec §5.4):
- `start_date` (string, ISO 8601; default 7 days ago)
- `end_date` (string, ISO 8601; default now)
- `symptom_type` (string)
- `food_keyword` (string)
- `limit` (number; default 20)

- [ ] Write the file at `hearty-mcp/src/tools/query-history.ts`
- [ ] TypeScript compile-check:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsc --noEmit 2>&1 | head -40
  ```
  No errors in `query-history.ts` before moving on.

**Deviation Log:** _None_

---

### Task 4.2: Implement src/tools/get-trends.ts

**Status:** 🟢 Completed

Implement `hearty-mcp/src/tools/get-trends.ts`. The tool name, description, and `inputSchema` must match spec §5.5 exactly. Handler behavior is partially deferred (see phase note above).

Function signature:
```typescript
export function registerGetTrends(server: McpServer): void
```

Handler behavior (spec §5.5, with Spec 07 deferral):
1. Call `getUserId()` to get `userId`
2. Query `food_triggers` table for this user, filtered by `focus_symptom` (if provided) and `occurrences >= min_occurrences` (default 2)
3. Check if any results exist and whether `last_updated` is within 24 hours:
   - If `food_triggers` has fresh data: return ranked triggers with `confidence_score`, `avg_severity`, `avg_onset_minutes`
   - If `food_triggers` is empty OR stale (no rows, or `last_updated` > 24h ago):
     Return `{ triggers: [], note: "Trend analysis not yet available — will activate once food intelligence (Spec 07) is deployed." }`
   - **Do NOT call** `run_trend_analysis()` RPC — defer to Spec 07
4. Inject health profile context
5. Wrap all logic in the standard try/catch pattern (spec §7)

`inputSchema` properties (all optional — from spec §5.5):
- `analysis_period_days` (number; default 30)
- `focus_symptom` (string)
- `min_occurrences` (number; default 2)

- [ ] Write the file at `hearty-mcp/src/tools/get-trends.ts`
- [ ] TypeScript compile-check:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsc --noEmit 2>&1 | head -40
  ```
  No errors in `get-trends.ts` before moving on.

**Deviation Log:** _None_

---

### Task 4.3: Implement src/tools/get-summary.ts

**Status:** 🟢 Completed

Implement `hearty-mcp/src/tools/get-summary.ts`. The tool name, description, `inputSchema`, and handler behavior must match spec §5.6 exactly.

Function signature:
```typescript
export function registerGetSummary(server: McpServer): void
```

Handler behavior (spec §5.6):
1. Call `getUserId()` to get `userId`
2. Resolve date range from `period` param: `"week"` = last 7 days, `"month"` = last 30 days, `"custom"` = `start_date` / `end_date` (both required if custom)
3. Query and aggregate:
   - `meals`: count of meals in range
   - `symptoms`: frequency grouped by `symptom_type`
   - `food_triggers`: top trigger foods (up to 5) for this user
   - `wellbeing_snapshots`: averages for `energy_level`, `mood`, `stress_level`, `sleep_hours`, `sleep_quality`
4. Return structured JSON — Claude synthesizes the narrative from this data (tool does not call any LLM)
5. Inject health profile context
6. Wrap all logic in the standard try/catch pattern (spec §7)

`inputSchema` properties (from spec §5.6):
- `period` (string enum: week, month, custom)
- `start_date` (string; required if `period` is `"custom"`)
- `end_date` (string; required if `period` is `"custom"`)

- [ ] Write the file at `hearty-mcp/src/tools/get-summary.ts`
- [ ] TypeScript compile-check:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsc --noEmit 2>&1 | head -40
  ```
  No errors in `get-summary.ts` before moving on.

- [ ] Commit all three query tool files:
  ```bash
  git -C /home/evan/projects/food-journal-assistant add hearty-mcp/src/tools/query-history.ts hearty-mcp/src/tools/get-trends.ts hearty-mcp/src/tools/get-summary.ts
  git -C /home/evan/projects/food-journal-assistant commit -m "feat: implement query_history, get_trends, get_summary tools"
  ```

**Deviation Log:** _None_

---

## Phase 5: Server Entrypoint & Hearty Persona

**Status:** 🟢 Completed
**Goal:** Implement `src/index.ts` — register all six tools, attach the full Hearty system prompt as the server `description`, and wire the stdio transport.
**Depends on:** Phases 3 and 4 complete

### Activation Prompt

```
You are implementing Phase 5 (Server Entrypoint & Hearty Persona) of the
Hearty MCP Server setup.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-02-mcp-server.md  (sections 3, 9)
- Plan: docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md
- Source file to implement: hearty-mcp/src/index.ts

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Task 5.1 and Task 5.2 in order.
When both tasks are done:
- Mark Phase 5 status as 🟢 Completed in the plan file
- Commit all changed files
- Tell me to run /compact
- Remind me that the Phase 6 Activation Prompt is at the top of Phase 6 in this plan file
```

---

### Task 5.1: Implement src/index.ts

**Status:** 🟢 Completed

Implement `hearty-mcp/src/index.ts` from spec §9, with the full system prompt from spec §3 inserted as the `description` field:

```typescript
// src/index.ts

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { registerLogMeal } from './tools/log-meal.js';
import { registerLogSymptoms } from './tools/log-symptoms.js';
import { registerLogWellbeing } from './tools/log-wellbeing.js';
import { registerQueryHistory } from './tools/query-history.js';
import { registerGetTrends } from './tools/get-trends.js';
import { registerGetSummary } from './tools/get-summary.js';

const server = new McpServer({
  name: 'hearty',
  version: '1.0.0',
  description: `<PASTE FULL SYSTEM PROMPT FROM SPEC §3 HERE>`
});

registerLogMeal(server);
registerLogSymptoms(server);
registerLogWellbeing(server);
registerQueryHistory(server);
registerGetTrends(server);
registerGetSummary(server);

const transport = new StdioServerTransport();
await server.connect(transport);
```

- [ ] Copy the full system prompt text verbatim from spec §3 (the block starting "You are Hearty, a compassionate and precise...") into the `description` field
- [ ] Verify all 6 import paths use `.js` extension (required by `NodeNext` module resolution)
- [ ] Write the file at `hearty-mcp/src/index.ts`

**Deviation Log:** _None_

---

### Task 5.2: Full TypeScript build and Claude Desktop config

**Status:** 🟢 Completed

- [ ] Full TypeScript build:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npm run build
  ```
  Expected: `dist/` directory created, `dist/index.js` exists, zero TypeScript errors.
  If there are errors, fix them before moving on.

- [ ] Verify the build output:
  ```bash
  ls /home/evan/projects/food-journal-assistant/hearty-mcp/dist/
  ```
  Expected — at minimum:
  ```
  dist/index.js
  dist/supabase.js
  dist/context.js
  dist/tools/log-meal.js
  dist/tools/log-symptoms.js
  dist/tools/log-wellbeing.js
  dist/tools/query-history.js
  dist/tools/get-trends.js
  dist/tools/get-summary.js
  ```

- [ ] Create the `.env.example` based snippet for `claude_desktop_config.json` (for reference only — do not commit the actual config file):
  ```json
  {
    "mcpServers": {
      "hearty": {
        "command": "node",
        "args": ["/home/evan/projects/food-journal-assistant/hearty-mcp/dist/index.js"],
        "env": {
          "SUPABASE_URL": "https://your-project.supabase.co",
          "SUPABASE_SERVICE_KEY": "your-service-role-key",
          "HEARTY_USER_ID": "your-user-uuid"
        }
      }
    }
  }
  ```
  Save this as `hearty-mcp/claude_desktop_config.example.json` (committed; contains no secrets).

- [ ] Add `dist/` to `hearty-mcp/.gitignore`:
  ```bash
  echo "dist/" > /home/evan/projects/food-journal-assistant/hearty-mcp/.gitignore
  echo ".env" >> /home/evan/projects/food-journal-assistant/hearty-mcp/.gitignore
  echo "node_modules/" >> /home/evan/projects/food-journal-assistant/hearty-mcp/.gitignore
  ```

- [ ] Commit:
  ```bash
  git -C /home/evan/projects/food-journal-assistant add hearty-mcp/src/index.ts hearty-mcp/.gitignore hearty-mcp/claude_desktop_config.example.json
  git -C /home/evan/projects/food-journal-assistant commit -m "feat: add server entrypoint, hearty persona, and build"
  ```

**Deviation Log:** _None_

---

## Phase 6: Integration Test

**Status:** 🟢 Completed
**Goal:** Connect the running MCP server to the real Supabase instance and exercise all six tools end-to-end. Verify rows land in the correct tables and the server handles error conditions gracefully.
**Depends on:** Phase 5 complete, Spec 01 plan 🟢 Completed (Supabase schema deployed and `.env` populated)

### Activation Prompt

```
You are running Phase 6 (Integration Test) for the Hearty MCP Server.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-02-mcp-server.md
- Plan: docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md
- Env file: hearty-mcp/.env  (must exist with all three vars populated)

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 6.1 through 6.4 in order.
When all tasks are done:
- Mark Phase 6 status as 🟢 Completed in the plan file
- Mark Plan Status as 🟢 Completed in the plan header
- Commit: git -C /home/evan/projects/food-journal-assistant add docs/superpowers/plans/2026-05-04-hearty-02-mcp-server-plan.md && git -C /home/evan/projects/food-journal-assistant commit -m "docs: mcp server plan complete"
- Tell me to run /compact
- Tell me this spec is done and Spec 03 (REST API) is next
```

---

### Task 6.1: Environment and startup check

**Status:** 🟢 Completed

- [ ] Confirm `.env` file exists with all three required variables:
  ```bash
  grep -c "SUPABASE_URL\|SUPABASE_SERVICE_KEY\|HEARTY_USER_ID" /home/evan/projects/food-journal-assistant/hearty-mcp/.env
  ```
  Expected: `3`

- [ ] Start the MCP server in dev mode and confirm it starts without errors:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsx src/index.ts &
  sleep 2 && echo "Server started"
  ```
  Expected: no error output. If you see `SUPABASE_URL and SUPABASE_SERVICE_KEY must be set` or `HEARTY_USER_ID must be set`, the `.env` is not being loaded — stop and investigate.

- [ ] Stop the background server:
  ```bash
  kill %1 2>/dev/null || true
  ```

**Deviation Log:** _None_

---

### Task 6.2: Test logging tools against Supabase

**Status:** 🟢 Completed

Write a test script at `hearty-mcp/scripts/integration-test.ts` that calls each tool handler directly (bypassing the MCP transport) against the real Supabase instance.

- [ ] Create `hearty-mcp/scripts/` directory:
  ```bash
  mkdir -p /home/evan/projects/food-journal-assistant/hearty-mcp/scripts
  ```

- [ ] Write `hearty-mcp/scripts/integration-test.ts` with the following test cases:

  **Test 1 — log_meal:**
  Call the handler directly with:
  ```typescript
  { description: "integration test meal — grilled salmon with rice", meal_type: "dinner", foods: [{ name: "grilled salmon" }, { name: "rice" }] }
  ```
  Assert: response contains `success: true` and a `meal_id` UUID. Capture `meal_id` for Test 2.

  **Test 2 — log_symptoms:**
  Call the handler with:
  ```typescript
  { meal_id: <from Test 1>, onset_minutes: 30, raw_description: "mild bloating", symptoms: [{ symptom_type: "bloating", severity: 3 }] }
  ```
  Assert: response contains `success: true`, `inserted: 1`.

  **Test 3 — log_wellbeing:**
  Call the handler with:
  ```typescript
  { energy_level: 7, mood: 8, sleep_hours: 7.5, notes: "integration test snapshot" }
  ```
  Assert: response contains `success: true`.

  **Test 4 — query_history:**
  Call the handler with `{ food_keyword: "salmon", limit: 5 }`
  Assert: response includes the meal from Test 1.

  **Test 5 — get_trends:**
  Call the handler with `{ analysis_period_days: 30 }`
  Assert: response contains either ranked triggers or the deferral note — no thrown error.

  **Test 6 — get_summary:**
  Call the handler with `{ period: "week" }`
  Assert: response contains `meal_count`, `symptom_frequency`, and no thrown error.

- [ ] Run the test script:
  ```bash
  cd /home/evan/projects/food-journal-assistant/hearty-mcp && npx tsx scripts/integration-test.ts
  ```
  All 6 tests must pass. Fix any failures before moving on.

**Deviation Log:** [2026-05-04] — Test 2 FAIL: `symptoms` table missing flat columns that `log-symptoms.ts` inserts (`symptom_type`, `severity`, `duration_minutes`, `bathroom_urgency`, `bathroom_visits`, `stool_consistency`). Deployed schema uses `severity_overall` + `structured_data JSONB` instead. `query-history.ts` nested select `symptoms(symptom_type, severity)` will also fail. Schema migration needed before tests can pass.

---

### Task 6.3: Test error handling

**Status:** 🟢 Completed

- [ ] Add a Test 7 to the integration test script: pass an invalid/missing `HEARTY_USER_ID` and confirm the tool returns `{ success: false, isError: true }` rather than throwing an unhandled exception.

  ```typescript
  // Temporarily unset HEARTY_USER_ID
  const saved = process.env.HEARTY_USER_ID;
  delete process.env.HEARTY_USER_ID;
  const result = await logMealHandler({ description: "error test" });
  process.env.HEARTY_USER_ID = saved;
  console.assert(result.isError === true, "Test 7 FAIL: expected isError: true");
  console.log("Test 7 PASS: error handling returns isError: true");
  ```

- [ ] Run: all 7 tests must pass.

**Deviation Log:** _None_

---

### Task 6.4: Cleanup and verification

**Status:** 🟢 Completed

- [ ] Delete the integration test rows from Supabase (use `supabase db execute` or the Supabase Dashboard SQL editor):
  ```sql
  DELETE FROM meals WHERE description ILIKE '%integration test%';
  DELETE FROM wellbeing_snapshots WHERE notes = 'integration test snapshot';
  ```

- [ ] Verify `dist/` is excluded from git:
  ```bash
  git -C /home/evan/projects/food-journal-assistant status hearty-mcp/dist 2>/dev/null | grep -q "ignored" && echo "dist/ is ignored" || echo "WARNING: dist/ is not gitignored"
  ```

- [ ] Commit the integration test script:
  ```bash
  git -C /home/evan/projects/food-journal-assistant add hearty-mcp/scripts/integration-test.ts
  git -C /home/evan/projects/food-journal-assistant commit -m "test: add mcp server integration test script"
  ```

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X, Task Y — changed X because Y`_

[2026-05-04] — Phase 4, Task 4.2 — get_trends does not call run_trend_analysis() RPC because that RPC is defined in Spec 07 (Food Intelligence), not Spec 01; returns empty triggers + deferral note instead
[2026-05-04] — Phase 1, Task 1.1 — added zod ^3.0.0 to dependencies; SDK 1.29.0 declares it as a required peer dependency (README: "npm install @modelcontextprotocol/sdk zod")
[2026-05-04] — Phases 3–4 — server.tool() deprecated in SDK 1.29.0; using server.registerTool() with Zod raw shapes for all tool inputSchema definitions instead of plain JSON Schema objects
[2026-05-04] — Phase 6, Task 6.2 — BLOCKED: integration test found schema/handler mismatch. The deployed `symptoms` table has columns `severity_overall` (not `severity`) and `structured_data JSONB` with no `symptom_type`, `duration_minutes`, `bathroom_urgency`, `bathroom_visits`, or `stool_consistency` flat columns. The `log-symptoms.ts` handler inserts these as flat fields and `query-history.ts` selects them — both will fail against the live schema. A new migration is needed to add the missing columns (or the handler must be rewritten to use `structured_data JSONB`). Until resolved, Tasks 6.2, 6.3, 6.4 cannot complete.
[2026-05-05] — Phase 6 — symptoms table missing flat columns (symptom_type, severity, etc.) per MCP spec; applied migration 20260505035200_symptoms_flat_columns.sql to add them; also fixed food_triggers.occurrence_count column name (handlers had 'occurrences')

---

## Notes

- **run_trend_analysis RPC** (Phase 4, Task 4.2): returns `triggers: []` until Spec 07 deploys the trend engine. Revisit `get-trends.ts` at the start of the Spec 07 plan to enable the RPC call and remove the deferral note.
- **Multi-user JWT auth**: spec §6.1 notes this as a future path. Current implementation is single-user via `HEARTY_USER_ID` env var + service role key. Auth model change would require replacing `getUserId()` with JWT extraction from the MCP request context.
- **Offline mode**: spec §8 explicitly scopes the MCP server as always-online. Flutter app offline queue is handled in Spec 04.
- **Claude Desktop config path**: the example config in `claude_desktop_config.example.json` uses an absolute path pinned to this machine. Anyone else using this server should update the `args` path accordingly.
- **`@modelcontextprotocol/sdk` API surface**: the spec shows `McpServer` + `server.tool()` from the high-level SDK. Verify against the installed README in Phase 3 and Phase 4 before writing handlers — if the signature differs, stop rather than adapting silently.
