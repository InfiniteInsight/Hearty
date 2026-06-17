# Idea: Tap a detected food to "search & change" it (vision → lookup bridge)

**Status:** Captured (not yet brainstormed). Raised during the on-device AI-vision test, 2026-06-17.
**Next step:** brainstorming → spec → plan → subagent build, as its own increment/branch.

## Problem
After a food-plate photo is analyzed (Spec 06 AI Vision), the result screen shows identified foods (`name` + `portion` + `confidence`). Vision is imperfect — some items are wrong or vague. The user wants to **tap a detected food and search for the correct one** to fix it.

## Decided behavior (locked with the user)
Tapping a detected food → a **search field** → searching runs the **food-intelligence lookup** (`POST /api/food/lookup`, `type: "name"`) → user picks a real result → it **replaces the detected item's name AND attaches that result's nutrition** (calories/macros) to the entry.

This is the **vision → lookup integration we deferred**, arriving via a user-driven correction path instead of an automatic one. Net effect: a corrected food carries real nutrition, not just a fixed label.

## Why this is the natural next increment
- Vision (Spec 06, PR #3) produces identification-only foods (no nutrition).
- Food Intelligence (Spec 07, PR #4) turns a name → structured nutrition via the tiered pipeline.
- "Search & change" is the UX seam that connects them: the result screen's food list becomes editable, and each edit is a lookup.

## Sketch (to be refined in brainstorming)
- **Flutter:** make each food row in `experiment`/photo result view... → specifically the photo result list (`features/photos/`) tappable → a search sheet (debounced query → `hearty_api_client` calls a food-search/lookup method → results list → tap to select → replace the row's name + nutrition). Keep portion editable too. Confirmed foods flow into the existing meal-logging path.
- **Backend:** reuse `POST /api/food/lookup` (already built, PR #4). May want a lighter `type: "name"` search that returns a few candidates rather than a single best result — decide in brainstorming (current lookup returns one tiered result; a "search" UX may want a candidate list, which could mean a new/expanded endpoint or surfacing OFF/Nutritionix multi-results).

## Dependencies / sequencing
- Live "search" requires the **`food_cache` migration applied** (currently deferred behind the PR #2 → #3 → #4 merge sequence) — sequence the merges + `db push` from master first, or apply the migration.
- Builds on both PR #3 (vision result UI) and PR #4 (lookup). Cleanest after both merge to master.

## Open questions for brainstorming
- Single best-match (current `lookup_food`) vs a **candidate list** to choose from (likely needs an endpoint that returns multiple OFF/Nutritionix hits).
- Should the same edit affordance also let the user **add** a missed food (not just change a detected one) and **delete** a wrong detection?
- How corrected+enriched foods map onto the meal `foods` JSONB (carry nutrition + a `source` so it's distinguishable from raw vision output).
