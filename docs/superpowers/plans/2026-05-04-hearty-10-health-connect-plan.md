# Hearty — Health Connect Integration (Spec 10) — Living Plan

**Spec:** [`hearty-10-health-connect.md`](../specs/2026-05-04-hearty-10-health-connect.md)  
**Roadmap Phase:** Future Phase (Android; implement after Spec 04 Android app is stable)  
**Plan Status:** 🔴 Not Started  
**Last Updated:** 2026-05-04  
**Last Verified Against Spec:** 2026-05-04 — re-verify if spec has changed since  
**Open Deviations:** 0

> **FUTURE PHASE — Re-verify before execution.**  
> This plan was written speculatively. Before beginning any phase, confirm that all prerequisite specs are complete and that all technologies named here (Android Health Connect API, `androidx.health.connect:connect-client`, the `health` Flutter package) are still current. The Health Connect permission model and minimum API level requirements have evolved quickly — re-check before writing any code.

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
| 0 | Review & Align | 🔴 Not Started | Spec 04 complete | Claude (start of every session) |
| 1 | Permissions Setup | 🔴 Not Started | Phase 0 | Mixed |
| 2 | Read Health Data | 🔴 Not Started | Phase 1 | Claude |
| 3 | Write Health Data | 🔴 Not Started | Phase 2 | Claude |
| 4 | Sync Strategy & Settings UI | 🔴 Not Started | Phases 2–3 | Mixed |

---

## Phase 0: Review & Align

**Status:** 🔴 Not Started  
**Goal:** Verify prerequisites are complete, confirm the spec and environment are current, and identify which phase to begin.  
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty Health Connect Integration plan.
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

IMPORTANT: This is a future/moonshot spec. Before detailing any tasks, verify
that all prerequisite specs are complete and that the technologies referenced
are still current — versions and APIs may have changed significantly since this
plan was written.

Working directory: /home/evan/projects/food-journal-assistant

Steps:

1. Read both files in full:
   - docs/superpowers/plans/2026-05-04-hearty-10-health-connect-plan.md
   - docs/superpowers/specs/2026-05-04-hearty-10-health-connect.md

2. Verify prerequisite specs are complete:
   - Spec 04 (Android app): check its plan file for 🟢 Completed status
   - If Spec 04 is not complete, this plan cannot proceed — report that clearly

3. Check the dev environment:
   - flutter --version
   - git status
   - Confirm minimum Android SDK target in android/app/build.gradle (need API 28+)

4. Re-verify current status of named technologies:
   - `health` Flutter package (pub.dev) — current version, maintenance status,
     and whether it supports the latest Android Health Connect permission model
   - `androidx.health.connect:connect-client` — current stable version
   - Health Connect minimum Android version requirements — still API 28, or higher?
   - The `health_permissions` intent filter pattern in AndroidManifest.xml — still required?

5. Check database prerequisites — the spec requires a `health_metrics` table.
   Verify it exists in the Supabase schema (check Spec 01's migration files or
   the Supabase dashboard). If it is absent, note it as a blocking prerequisite:
   a new migration must be added before Phase 1 can begin.

6. Spec drift check — the plan was written on 2026-05-04. Scan the spec for any
   changes to permission names, data type record names, or sync strategy.
   List any conflicts found.

7. Report:
   - Prerequisites: Spec 04 complete or blocked; `health_metrics` table exists or missing
   - Environment: what is/isn't installed or configured
   - Technology currency: any outdated or renamed items found
   - Spec alignment: drift found, or "clean"
   - Next action: which phase to proceed with, or what to resolve first

Before running any command, verify it exists with --help or equivalent.
If a command doesn't behave as expected, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
```

**Deviation Log:** _None_

---

## Phase 1: Permissions Setup

**Status:** 🔴 Not Started  
**Goal:** Add all required Health Connect permission declarations to the Android manifest and implement the in-app permission request flow with user-facing justification screens.  
**Depends on:** Phase 0 (prerequisites verified, `health_metrics` table confirmed)  
**Type:** Mixed

**Key deliverables:**
- All required `android.permission.health.*` entries added to `AndroidManifest.xml`
- `health_permissions` `activity-alias` intent filter added to `AndroidManifest.xml`
- In-app explanation screen built: lists which data types will be read and why
- Permission request flow implemented: explanation → system Health Connect dialog → result stored in user preferences
- Each health data type independently toggleable in Settings > Integrations

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 2: Read Health Data

**Status:** 🔴 Not Started  
**Goal:** Pull sleep, steps, heart rate, and exercise session data from Health Connect and store it in the `health_metrics` table for use by the AI correlation engine.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- `health` Flutter package integrated; `SleepSessionRecord`, `StepsRecord`, `HeartRateRecord`, `ExerciseSessionRecord` reads implemented
- On-open pull: last 24 hours of data fetched for each granted data type
- Incremental sync: `last_health_sync_at` timestamp stored per data type; subsequent opens pull only new records
- Pulled records stored in `health_metrics` table under the user's `auth.uid()` RLS policy
- At-launch data type decision documented (sleep + steps only, or include exercise + heart rate — decide at phase start)

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 3: Write Health Data

**Status:** 🔴 Not Started  
**Goal:** Write Hearty's resolved nutrition logs back to Health Connect as `NutritionRecord` entries, with failure queuing.  
**Depends on:** Phase 2  
**Type:** Claude

**Key deliverables:**
- `NutritionRecord` write implemented immediately after a meal is saved with resolved nutritional data
- Write skipped when `data_source: "unknown"` — only write when nutrition data is available
- Failed writes queued and retried on next sync; meal logging never blocked by a failed write
- Write-back toggle in Settings: user can disable independently of read access
- Write behavior verified against a test Health Connect dataset on a physical device or emulator

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 4: Sync Strategy & Settings UI

**Status:** 🔴 Not Started  
**Goal:** Complete the sync architecture — incremental sync, failure handling, and Settings > Integrations UI — and verify end-to-end data flow into the correlation engine.  
**Depends on:** Phases 2–3  
**Type:** Mixed

**Key deliverables:**
- Settings > Integrations > Health Connect screen: per-data-type toggles, last-synced timestamps, disconnect option
- In-app disclosure text displayed before first permission request (spec Section 7 language)
- "Delete Health Connect Data" action in Settings > Data implemented
- Sync behavior verified: pull-on-open works; incremental timestamp prevents duplicate records
- `health_metrics` data confirmed visible to Phase 4 AI correlation queries (or placeholder verified if Phase 4 is not yet complete)

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X — changed X because Y`_

---

## Notes

- **`health_metrics` table:** The spec requires this table to be created in Spec 01's schema. If Spec 01 was executed without it, a new migration must be added before this plan's Phase 1 can begin. Phase 0 will surface this.
- **Phase 4 AI Intelligence dependency:** Health Connect data is most valuable when the Phase 4 correlation engine (Spec 07 Food Intelligence) is complete. This plan can collect and store data before Phase 4, but insights will not appear until that engine is in place.
- **iOS HealthKit:** The `health` Flutter package supports both Health Connect and HealthKit. The decision of whether to implement HealthKit at the same time as this spec, or defer it to Spec 09 (iOS), should be made at Phase 0 time.
- **Body weight:** The spec marks body weight as optional and potentially intrusive. The decision to include `WeightRecord` at launch should be made at the start of Phase 1.
