# Idea: Correct the foods a photo detected (editable detected-food list)

**Status:** Captured + re-scoped 2026-06-19. Not yet brainstormed.
**Next step:** brainstorming → plan → build, as its own increment/branch.

## Problem
After a food-plate photo is analyzed (Spec 06 AI Vision), the result screen (`features/photos/screens/photo_review_screen.dart`) shows the detected foods **read-only** (you can only edit the free-text description). Vision is imperfect — some items are wrong, vague, missed, or spurious. The user wants to **correct the detected food list** before it's logged.

## Decided scope (corrected with the user 2026-06-19)
This is about **tracking *what was eaten*, NOT nutrition.** Hearty is a food/symptom trigger journal, not a calorie counter (and the specs already say "no calories from photos"). So:
- ❌ NO nutrition / calories / macros, NO food-intelligence `/api/food/lookup` involvement, NO candidate "search" against a nutrition DB.
- ✅ Just let the user **edit a detected food's name, remove a wrong detection, and add a missed food** — plain food names — so the logged meal's `foods` list is accurate.

## Key finding — reuse what just merged
`EditMealScreen` (`features/logging/screens/edit_meal_screen.dart`, merged via the food-editing work) **already** provides editable foods: per-food `TextEditingController`s, `_removeFood`, add, dirty-tracking, and save via meal `PATCH` with a `foods` list. The photo flow should **reuse this**, not rebuild food-editing.

## Likely approach (to confirm in brainstorming)
**Option A (preferred, minimal):** after a photo is processed, route the detected food names into `EditMealScreen(initialFoods: [...])` so the user corrects/removes/adds there and saves through the existing path. Near-zero new infrastructure.
**Option B:** make the detected-food rows in `photo_review_screen.dart` inline-editable (replicate the EditMealScreen per-food edit/remove/add in the review screen). More code; keeps editing in the photo flow.

## Open questions for brainstorming
- A vs B (reuse EditMealScreen vs inline-edit on the review screen).
- Keep `portion`/`confidence` (vision metadata) visible while editing, or drop to plain names once the user takes over?
- Where "add a missed food" lives, and how the confirmed list flows into the meal `foods` (the merged PATCH already accepts a foods list).
- Backend: almost certainly **none** needed (pure Flutter, reusing the existing meal-foods PATCH). Confirm.

## Dependencies
- None blocking. Pure Flutter; builds on the merged food-editing (`EditMealScreen` + meal `PATCH` foods) and the vision result screen — both on master.
