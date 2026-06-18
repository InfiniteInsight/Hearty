# Bug/polish: surface friendly category labels, not raw slugs (e.g. "dairy_casein")

**Status:** Captured during the on-device experiments test, 2026-06-17.
**Severity:** Minor UX (functional, but user-facing text shows internal slugs).

## Finding
The food classifier (`food_category_service`) emits granular internal categories like `dairy_casein`, `fodmap_lactose`, `fodmap_fructose`, `histamine`. These slugs leak into user-facing UI:
- The **experiment nudge dialog** says e.g. *"Noticed dairy_casein in a few meals…"* (`features/experiments/widgets/experiment_nudge_dialog.dart`).
- The **start chip** ("Test this — cut {category} for 2 weeks?") and the **result screen** copy interpolate the raw `category` too (`experiment_result_screen.dart`).
- Likely also the trends conversation / signal surfaces wherever a category is shown.

Users see `dairy_casein` instead of something like "dairy (casein)" or just "dairy".

## Fix direction
Add a single mapping from internal category slug → human label (one source of truth, backend or shared), and run all user-facing category text through it. Keep the slug as the stored/logic value (experiments.category, signals, lookup) — only the *display* changes.
- Backend: a `CATEGORY_LABELS` dict in `food_category_service` (or a small `category_labels.py`) + include a `category_label` alongside `category` in API responses that surface it (proposed_experiment, experiment responses, signals).
- Flutter: render the label, fall back to a prettified slug (`replaceAll('_',' ')`/title-case) if no mapping.

## Scope note
Cross-cutting (experiments + trends/signals + the future vision→lookup edit UI all show categories). Worth doing once, centrally, before more category-facing UI lands.
