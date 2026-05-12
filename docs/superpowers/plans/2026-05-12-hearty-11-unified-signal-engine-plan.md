# Hearty — Plan 11: Unified Signal Engine

**Plan Status:** 🟡 Ready for implementation
**Last Updated:** 2026-05-12

---

## Context

Strategic gap identified via Wardley Map analysis: the correlation engine (`trend_engine.py`) is the highest-value, least-developed component in the project. The current engine is a co-occurrence counter with no counterfactual, a fixed 4-hour onset window, and no connection to the wellbeing snapshot data.

This plan redesigns it as a **Unified Signal Engine** combining three improvements:
- **A: Counterfactual base rate** — compare symptom/wellbeing rates *with* vs *without* a given food category
- **B: Multi-window discovery** — test multiple onset windows, report where signal peaks
- **C: Wellbeing integration** — use morning/midday/evening snapshots as continuous outcome variables alongside discrete symptom events

---

## Design Decisions (all resolved)

### 1. Food normalization: LLM + fixed taxonomy
Foods logged as raw strings (e.g. "grilled chicken breast") will be classified by an LLM pass into a fixed taxonomy of categories before analysis. The engine analyzes at the category level, not the raw food name level. A food can belong to multiple categories.

### 2. Food category taxonomy (18 categories, research-validated)

Validated against Monash FODMAP literature, Rome IV, FDA Big-9, and clinical IBS research.

| Category | Example foods | Notes |
|---|---|---|
| `fodmap_fructans` | garlic, onion, leek, shallots, wheat, rye, barley | Wheat overlaps with `gluten` |
| `fodmap_fructose` | apples*, pears*, honey, mango, HFCS | *also in `fodmap_polyols` |
| `fodmap_polyols` | stone fruits, mushrooms, sorbitol/xylitol/mannitol sweeteners | Polyol-class only; not sucralose/aspartame |
| `fodmap_gos` | beans, lentils, chickpeas, whole soy milk | Renamed from "galactans" per Monash terminology |
| `fodmap_lactose` | milk, yogurt, soft cheese, ice cream | Enzyme deficiency mechanism |
| `dairy_casein` | all dairy incl. butter, aged/hard cheese | Protein sensitivity; different food list from lactose |
| `gluten` | wheat, barley, rye, spelt | Overlaps `fodmap_fructans` for wheat; keep both |
| `eggs` | egg white (primary allergen), egg yolk | FDA Big-9; not captured by other categories |
| `soy` | soy milk, tofu, tempeh, edamame, soy sauce | FDA Big-9; distinct from GOS content |
| `histamine` | aged cheese, red wine, cured meats, fermented foods, tinned fish | DAO enzyme pathway |
| `sulfites` | dried fruit, white wine, shrimp, deli meats, vinegar | Sulfite oxidase pathway; distinct from histamine |
| `caffeine` | coffee, tea, energy drinks, dark chocolate* | *dark chocolate also in `histamine` |
| `alcohol` | wine, beer, spirits | DAO inhibitor; overlaps histamine/sulfites |
| `high_fat` | fried food, fatty cuts, cream sauces, pastries, desserts | |
| `cruciferous` | broccoli, cauliflower, cabbage, brussels sprouts | Some GOS overlap |
| `nightshades` | tomato, peppers, eggplant | Provisional/low-evidence; potato removed |
| `high_sugar_refined` | HFCS drinks, soda, candy, syrups | Narrowed from "high_sugar"; pastries → `high_fat` |
| `spicy` | hot peppers, chilli, hot sauce | TRPV1 mechanism |

Multi-category foods: apples/pears (fructose+polyols), red wine (alcohol+histamine), white wine (alcohol+sulfites), dark chocolate (caffeine+histamine), aged cheese (dairy_casein+histamine), wheat/bread/pasta (gluten+fodmap_fructans).

### 3. Database: new `food_signals` table
New `food_signals` table with different shape from `food_triggers`. `food_triggers` deprecated but kept temporarily for backward compatibility. All new reads and writes go to `food_signals`.

### 4. Sleep: outcome variable, not filter
`sleep_quality` and `sleep_hours` are outcome variables alongside energy and mood. Food → GI distress → poor sleep is a causal pathway — filtering on sleep would remove valid signal. Noise from non-food causes won't correlate consistently with any category.

### 5. Ranking: unified score with channel breakdown
Single ranked list ordered by `unified_score`. A food category with signals in both symptom and wellbeing channels scores higher than one with signals in only one (convergence is structural). Each item shows per-channel breakdown: outcome name, onset window or slot pair, relative risk or score delta, direction (harmful/beneficial).

### 6. Minimum data thresholds (defaults, all tunable)
- `MIN_EXPOSED_MEALS = 3` — minimum meals containing category before analysis
- `MIN_UNEXPOSED_MEALS = 5` — minimum baseline (without category) to compute counterfactual
- `MIN_WB_SAMPLES = 3` — minimum wellbeing snapshots per slot pair
- `MIN_RR = 1.5` — minimum relative risk to surface a symptom signal
- `MIN_WB_DELTA = 0.5` — minimum score delta (out of 10) to surface a wellbeing signal

### 7. When to run: background job with three trigger modes
1. **Nightly schedule** — guaranteed baseline run
2. **Opportunistic idle** — Android WorkManager (`IDLE` constraint) / iOS BGProcessingTask; fires only when new meals or wellbeing logs exist since `last_analyzed_at`
3. **Manual re-run** — user-triggered from trends screen at any time

Server tracks `last_analyzed_at` per user. Idle trigger pre-checks for new data before starting. Dedicated `POST /api/trends/analyze` endpoint is the backend trigger for all three modes.

---

## Components affected

| Layer | What changes |
|---|---|
| DB | New `food_signals` table; `last_analyzed_at` tracking; `food_triggers` deprecated |
| Python services | New `food_category_service.py`; rewrite `trend_engine.py` → `signal_engine.py` |
| Python API | New Pydantic models in `schemas.py`; updated + new endpoints in `routers/trends.py` |
| Flutter models | `trends_data.dart` — new `FoodSignal`, `SignalChannel` models |
| Flutter UI | `trends_screen.dart` — new ranked signal card design + re-run button |
| Flutter background | New `AnalysisWorker.kt` (Android) + BGProcessingTask registration (iOS) |
| Chat context | `chat.py` — health context injection reads from `food_signals` |

---

## Phase Summary

| Phase | Name | Status |
|---|---|---|
| 1 | DB migration | 🔵 Not started |
| 2 | Food category service | 🔵 Not started |
| 3 | Signal engine rewrite | 🔵 Not started |
| 4 | API updates | 🔵 Not started |
| 5 | Flutter model + UI | 🔵 Not started |
| 6 | Background job infrastructure | 🔵 Not started |
| 7 | Chat context update | 🔵 Not started |

---

## Phase 1: DB Migration

**Goal:** Create `food_signals` table; add `last_analyzed_at` tracking; deprecate `food_triggers`.

### Tasks
- [ ] Create `supabase/migrations/20260512000000_food_signals.sql`
- [ ] Create `food_signals` table:
  ```sql
  CREATE TABLE food_signals (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES auth.users NOT NULL,
    category            TEXT NOT NULL,
    outcome_type        TEXT NOT NULL CHECK (outcome_type IN ('symptom', 'wellbeing')),
    outcome_name        TEXT NOT NULL,
    direction           TEXT NOT NULL CHECK (direction IN ('harmful', 'beneficial')),
    peak_window_minutes INT,           -- symptom signals: onset window where RR peaks
    meal_slot           TEXT,          -- wellbeing signals: breakfast/lunch/dinner/snack
    wellbeing_slot      TEXT,          -- wellbeing signals: morning/midday/evening
    relative_risk       NUMERIC(6,3),  -- symptom signals
    score_delta         NUMERIC(6,3),  -- wellbeing signals (positive = beneficial)
    unified_score       NUMERIC(5,4),  -- 0–1 normalised, used for ranking
    evidence_count      INT NOT NULL DEFAULT 0,
    analyzed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  ```
- [ ] Add unique constraint: `(user_id, category, outcome_type, outcome_name, peak_window_minutes, meal_slot, wellbeing_slot)`
- [ ] Add index: `(user_id, unified_score DESC)`
- [ ] Enable RLS; add owner-only policy matching pattern of existing tables
- [ ] Add `last_analyzed_at TIMESTAMPTZ` column to `health_profiles` (or create `user_analysis_state` table if `health_profiles` is inappropriate)
- [ ] Add deprecation comment to `food_triggers` table definition; do not drop

---

## Phase 2: Food Category Service

**Goal:** LLM-powered food name → category classification, backed by the 18-category taxonomy.

### Tasks
- [ ] Create `hearty-api/app/services/food_category_service.py`
- [ ] Define `TAXONOMY: dict` — all 18 categories with slug, display name, example foods, and multi-category cross-references
- [ ] Define `MULTI_CATEGORY_FOODS: dict` — known overlapping foods (e.g. `"wheat": ["gluten", "fodmap_fructans"]`) as seed hints in the prompt
- [ ] Implement `classify_foods(food_names: list[str]) -> dict[str, list[str]]`:
  - Batch all unique food names into a single LLM call
  - Prompt instructs model to return JSON: `{"food_name": ["category_slug", ...], ...}`
  - Model must only use slugs from the taxonomy; unknown foods return `[]`
  - Validate response against known category slugs; drop invalid entries
- [ ] Add in-memory cache (simple dict) per analysis run to avoid re-classifying the same name
- [ ] Use `litellm` with `LLM_MODEL` env var, consistent with `ai_extraction.py`

---

## Phase 3: Signal Engine Rewrite

**Goal:** Replace `trend_engine.py` with `signal_engine.py` implementing counterfactual relative risk, multi-window discovery, wellbeing outcomes, and unified scoring.

### Constants
```python
ONSET_WINDOWS = [30, 60, 120, 240, 480, 720, 1440]  # minutes
WB_DIMENSIONS = ['energy_level', 'mood', 'stress_level', 'sleep_quality', 'sleep_hours']
MEAL_SLOTS    = ['breakfast', 'lunch', 'dinner', 'snack']
WB_SLOTS      = ['morning', 'midday', 'evening']
MIN_EXPOSED_MEALS   = 3
MIN_UNEXPOSED_MEALS = 5
MIN_WB_SAMPLES      = 3
MIN_RR              = 1.5
MIN_WB_DELTA        = 0.5
```

### Tasks
- [ ] Create `hearty-api/app/services/signal_engine.py`
- [ ] `load_data(user_id, period_days)` — fetch meals (with foods JSONB), symptoms, wellbeing snapshots from Supabase
- [ ] `build_category_exposure(meals, category_map)` → `dict[str, set[str]]` mapping category slug → set of meal IDs
- [ ] `compute_symptom_signals(category, exposed_ids, unexposed_ids, symptoms)`:
  - For each `window` in `ONSET_WINDOWS` × each `symptom_type`:
    - Compute `p_with` = proportion of exposed meals followed by that symptom within window
    - Compute `p_without` = same over unexposed meals
    - Laplace-smooth both to avoid divide-by-zero: `(count + 0.5) / (n + 1)`
    - `RR = p_with / p_without`
  - Keep only the window with highest RR per symptom type (peak window)
  - Drop signals where `RR < MIN_RR` or `evidence_count < MIN_EXPOSED_MEALS`
  - Return list of symptom signal dicts
- [ ] `compute_wellbeing_signals(category, exposed_ids, unexposed_ids, meals, wellbeing)`:
  - For each `(meal_slot, wb_slot, wb_dimension)` combination:
    - Match exposed meals eaten in `meal_slot` to wellbeing snapshots in `wb_slot` on same/next day
    - Same for unexposed meals
    - Skip if fewer than `MIN_WB_SAMPLES` in either group
    - `delta = mean(exposed_scores) - mean(unexposed_scores)`
    - Direction: `'beneficial'` if delta > 0 for energy/mood/sleep; `'harmful'` if delta < 0
    - Drop if `abs(delta) < MIN_WB_DELTA`
  - Return list of wellbeing signal dicts
- [ ] `compute_unified_score(symptom_signals, wellbeing_signals)`:
  - Normalise RR to 0–1: `(RR - 1) / (RR_MAX - 1)` capped at 1.0 (use `RR_MAX = 5.0`)
  - Normalise delta to 0–1: `abs(delta) / 10.0` capped at 1.0
  - Base score = max of all normalised signal scores for this category
  - Convergence multiplier: `1.0 + 0.2 * (number of channels with signals - 1)` capped at 1.4
  - `unified_score = min(base_score * convergence_multiplier, 1.0)`
- [ ] `run_analysis(user_id, period_days=90)`:
  - Orchestrates load → classify → expose → signals → score
  - Upserts all signals to `food_signals` using unique constraint
  - Deletes stale signals for this user not present in current run
  - Updates `last_analyzed_at`
  - Returns summary dict (categories analysed, signals found, duration)
- [ ] Keep `trend_engine.py` in place but deprecated with a module-level comment; it is still called by the legacy `update_food_triggers_table` path until Phase 7 is complete

---

## Phase 4: API Updates

**Goal:** New endpoint to trigger analysis; updated trends response using `food_signals`.

### New Pydantic models (`schemas.py`)
- [ ] `SignalChannel` — `outcome_type`, `outcome_name`, `direction`, `peak_window_minutes`, `meal_slot`, `wellbeing_slot`, `relative_risk`, `score_delta`, `evidence_count`
- [ ] `FoodSignal` — `category`, `unified_score`, `channels: list[SignalChannel]`, `convergent: bool`
- [ ] `SignalsResponse` — `signals: list[FoodSignal]`, `analyzed_at`, `total_meals_analyzed`, `total_symptoms_analyzed`, `total_wellbeing_analyzed`
- [ ] `AnalyzeResponse` — `status` (`'started'` | `'completed'`), `analyzed_at`, `new_signals_count`
- [ ] `AnalyzeStatusResponse` — `last_analyzed_at`, `has_new_data: bool`

### Endpoint changes (`routers/trends.py`)
- [ ] `GET /api/trends` — query `food_signals` for user, group by category, assemble `FoodSignal` list sorted by `unified_score DESC`; return `SignalsResponse`
- [ ] `POST /api/trends/analyze` — call `signal_engine.run_analysis(user_id)`; return `AnalyzeResponse`
- [ ] `GET /api/trends/analyze/status` — return `last_analyzed_at` + whether any meals or wellbeing logs exist after it (`has_new_data`)
- [ ] Retain existing `/api/trends/summary` endpoint (used by chat router) until Phase 7 is complete

---

## Phase 5: Flutter Model + UI

**Goal:** Update Flutter to consume new signal shape; redesign trends screen with ranked cards.

### Tasks
- [ ] Add `SignalChannel` and `FoodSignal` models to `trends_data.dart`
- [ ] Update `TrendsData` — replace `topTriggerFoods: List<TriggerFood>` with `signals: List<FoodSignal>`
- [ ] Update `hearty_api_client.dart` — parse new `SignalsResponse` shape; add `triggerAnalysis()` and `getAnalyzeStatus()` methods
- [ ] Update `trends_provider.dart` — add `triggerAnalysis()` action
- [ ] Redesign `trends_screen.dart`:
  - Ranked signal cards showing: category name, strength indicator (bar or stars), per-channel rows (outcome name, window label, RR or delta, direction arrow), convergent evidence badge (⚡) when `convergent == true`
  - "Analyse now" button → `triggerAnalysis()` → optimistic loading state → refresh
  - `last_analyzed_at` subtitle ("Last updated 3h ago")
  - Empty state: "Keep logging — patterns will appear once you have enough data"
- [ ] Keep `SymptomFrequencyPoint` and `WellbeingPoint` chart sections unchanged

---

## Phase 6: Background Job Infrastructure

**Goal:** Nightly scheduled analysis + opportunistic idle-triggered analysis on Android and iOS.

### Android (`AnalysisWorker.kt`)
- [ ] Create `hearty_app/android/app/src/main/kotlin/com/hearty/app/AnalysisWorker.kt`
- [ ] Extend `CoroutineWorker`; call `POST /api/trends/analyze/status` first — skip if `has_new_data == false`; otherwise call `POST /api/trends/analyze`
- [ ] Enqueue **periodic work** (nightly): `PeriodicWorkRequestBuilder<AnalysisWorker>(24, TimeUnit.HOURS)` with `NetworkType.CONNECTED` constraint
- [ ] Enqueue **one-time idle work** after each meal or wellbeing log: `OneTimeWorkRequestBuilder<AnalysisWorker>()` with `NetworkType.CONNECTED` + `DeviceIdle.DEVICE_IDLE` constraints; use `ExistingWorkPolicy.KEEP` so multiple logs don't queue duplicate runs
- [ ] Register both in `MainActivity.kt` on app start

### iOS
- [ ] Register `BGProcessingTask` identifier `com.hearty.app.analysis` in `Info.plist`
- [ ] In `AppDelegate.swift`, register handler: check `analyze/status`, skip if no new data, else call `POST /api/trends/analyze`
- [ ] Submit `BGProcessingTaskRequest` (requires network, permits CPU) after meal or wellbeing log

### Flutter coordination
- [ ] After successful meal log in `meals_provider.dart`, invoke platform channel or method channel to signal "new data" → triggers idle work enqueue on Android; BGProcessingTask submit on iOS
- [ ] After successful wellbeing log in `wellbeing_provider.dart`, same

---

## Phase 7: Chat Context Update

**Goal:** AI health context uses `food_signals` instead of `food_triggers`.

### Tasks
- [ ] Update `chat.py` health context injection to query top 5 `food_signals` by `unified_score` for the user
- [ ] Format signals as natural language: e.g. "Strong signal: gluten → bloating (2–4h, RR 2.4×) and lower sleep quality. Moderate signal: caffeine → higher morning energy."
- [ ] Remove `food_triggers` query from chat context path
- [ ] Once this phase is complete, `food_triggers` table and `trend_engine.py` can be formally deprecated and scheduled for removal
