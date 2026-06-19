# Friendly Category Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Stop raw category slugs (`dairy_casein`, `fodmap_lactose`, …) from leaking into user-facing UI. Surface the human `display` labels that already exist in the `food_category_service.TAXONOMY` (e.g. `dairy_casein` → "Dairy / Casein") everywhere a category is shown — experiments (nudge dialog, start chip, result) and signals/trends.

**Architecture:** One backend source of truth — a `category_label(slug)` helper reading `TAXONOMY[slug]["display"]` with a prettified-slug fallback. Add a `category_label` field to the four user-facing category-bearing response models and populate it at their build sites. Flutter renders the label with its own prettify fallback (so older cached payloads without the field still look right). Slugs remain the stored/logic value everywhere — only display changes.

**Tech Stack:** FastAPI + Pydantic; Flutter/Dart. Backend test runner: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest <file> -v`.

**Verified facts:**
- `hearty-api/app/services/food_category_service.py` has `TAXONOMY: dict[str, dict]` — 18 categories, each with a `"display"` string. No label helper exists yet.
- Category surfaces in responses: `experiments.py:20` `_to_response` (`category=row["category"]`); the trends conversation builds `ProposedExperiment`; `signal_presenter.py:56` builds `FoodSignal` (`category=s["category"]`) and also builds `ResolvedSignal` (~lines 89–113).
- Schemas in `app/models/schemas.py`: `ExperimentResponse`, `ProposedExperiment`, `FoodSignal`, `ResolvedSignal`.
- Dart models: `hearty_app/lib/core/api/models/experiment.dart` (`Experiment`, `ProposedExperiment`), `trends_data.dart` (`FoodSignal`, `ResolvedSignal`).

---

## Task 1: `category_label()` backend helper (TDD)

**Files:** Modify `hearty-api/app/services/food_category_service.py`; Test `hearty-api/tests/test_category_label_unit.py`

- [ ] **Step 1: Failing test**

```python
from app.services.food_category_service import category_label


def test_known_slug_returns_display():
    assert category_label("dairy_casein") == "Dairy / Casein"
    assert category_label("fodmap_lactose") == "FODMAP Lactose"
    assert category_label("histamine") == "High Histamine"


def test_unknown_slug_prettified_fallback():
    assert category_label("made_up_thing") == "Made Up Thing"


def test_empty_or_none_is_safe():
    assert category_label("") == ""
    assert category_label(None) == ""
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement** — add to `food_category_service.py` (near TAXONOMY):

```python
def category_label(slug: str) -> str:
    """Human-facing label for a category slug. Uses the TAXONOMY display name;
    falls back to a prettified slug for anything unknown. Empty/None -> ''."""
    if not slug:
        return ""
    entry = TAXONOMY.get(slug)
    if entry and entry.get("display"):
        return entry["display"]
    return slug.replace("_", " ").title()
```

- [ ] **Step 4: Run → pass (3 tests).**

- [ ] **Step 5: Commit** (`feat(labels): category_label helper from TAXONOMY display`).

---

## Task 2: Surface `category_label` on experiment responses (TDD)

**Files:** Modify `hearty-api/app/models/schemas.py`, `hearty-api/app/routers/experiments.py`, `hearty-api/app/services/trends_conversation.py`; Tests: extend `tests/test_experiments_endpoint_unit.py` + `tests/test_trends_conversation_unit.py`.

- [ ] **Step 1:** Add `category_label: Optional[str] = None` to `ExperimentResponse` and to `ProposedExperiment` in `schemas.py`.

- [ ] **Step 2:** Populate:
  - In `experiments.py` `_to_response`, import `category_label` from `food_category_service` and pass `category_label=category_label(row["category"])`.
  - In `trends_conversation.py` where `ProposedExperiment(**pe)` is built, set its `category_label` from `category_label(pe["category"])` (construct explicitly: `ProposedExperiment(category=pe["category"], outcome_type=..., outcome_name=..., category_label=category_label(pe["category"]))`, or set after parse).

- [ ] **Step 3: Tests** — assert the responses now include the friendly label:
  - In an experiments endpoint test (active or create), assert `body["category_label"] == "Dairy / Casein"` for a `dairy_casein` row (adjust an existing fixture's category to `dairy_casein`, or add a focused test).
  - In the conversation test that parses `proposed_experiment` (use category `dairy_casein`), assert `out.proposed_experiment.category_label == "Dairy / Casein"`.

- [ ] **Step 4:** Run those two files + full suite (`--ignore=tests/test_api.py`) → all pass.

- [ ] **Step 5: Commit** (`feat(labels): category_label on experiment + proposed-experiment responses`).

---

## Task 3: Surface `category_label` on signal responses (TDD)

**Files:** Modify `hearty-api/app/models/schemas.py`, `hearty-api/app/services/signal_presenter.py`; Test: extend the signal_presenter unit test (find it under `tests/`).

- [ ] **Step 1:** Add `category_label: Optional[str] = None` to `FoodSignal` and `ResolvedSignal` in `schemas.py`.

- [ ] **Step 2:** In `signal_presenter.py`, import `category_label` and set it wherever `FoodSignal(category=...)` and `ResolvedSignal(category=...)` are constructed (`category_label=category_label(<the category>)`).

- [ ] **Step 3: Test** — in the presenter's unit test, assert a built `FoodSignal`/`ResolvedSignal` carries the friendly `category_label` (e.g. a `dairy_casein` signal → "Dairy / Casein"). If no presenter unit test exists, add a focused one that drives the build path with a mocked supabase row.

- [ ] **Step 4:** Run the test file + full suite (`--ignore=tests/test_api.py`) → all pass.

- [ ] **Step 5: Commit** (`feat(labels): category_label on signal + resolved-signal responses`).

---

## Task 4 (CONTRACT — text-first): Flutter renders friendly labels

**Files:** Modify `hearty_app/lib/core/api/models/experiment.dart` (`Experiment`, `ProposedExperiment`), `hearty_app/lib/core/api/models/trends_data.dart` (`FoodSignal`, `ResolvedSignal`); the UI surfaces: `features/experiments/widgets/experiment_nudge_dialog.dart`, `features/experiments/screens/experiment_result_screen.dart`, `features/trends/screens/trends_conversation_screen.dart` (start chip), and any trends/signals widget that prints `signal.category`. Tests: extend the relevant model + widget tests.

> Add a `categoryLabel` field to each model, parsed from `category_label` with a **prettify fallback** so older/cached payloads still render nicely:
> `final String categoryLabel; ... categoryLabel: (json['category_label'] as String?)?.isNotEmpty == true ? json['category_label'] as String : _prettify(json['category'] as String? ?? '')` where `_prettify(s) => s.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase()+w.substring(1)).join(' ')`. (Factor `_prettify` into one shared helper, e.g. `lib/core/util/category_label.dart`, and reuse.)
> Then replace every user-facing use of the raw `category`/`outcomeName`-adjacent slug in those widgets with `categoryLabel` (nudge dialog body, start chip "cut {label} for 2 weeks?", result screen copy, signal/trend list rows). Keep using the raw `category` for any logic/keys/write-backs.

- [ ] Implement; update/add widget tests asserting the friendly label renders (e.g. nudge dialog shows "Dairy / Casein", not "dairy_casein"); `flutter test`; `flutter analyze lib/`; commit (`feat(labels): Flutter renders friendly category labels`).

---

## Self-review
- **Coverage:** helper (T1) · experiment + proposed-experiment (T2) · signal + resolved-signal (T3) · all Flutter category-facing surfaces (T4). Slugs remain the logic/stored value; only display changes.
- **Consistency:** backend `category_label(slug)` is the single source; Flutter has a matching prettify fallback for cache-safety. `category_label` field added to exactly the 4 models that carry a user-facing category.
- **No placeholders:** backend tasks have code; T4 is a contract task (the established pattern) with exact field-parsing + the surfaces to change.
