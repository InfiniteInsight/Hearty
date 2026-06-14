"""Unified Signal Engine.

Replaces trend_engine.py with statistically rigorous signal detection:
  - Counterfactual relative risk (exposed vs unexposed baseline)
  - Multi-window onset discovery (7 onset windows, keeps peak)
  - Wellbeing integration (continuous outcome variables alongside symptoms)
"""
import os
import time
from datetime import datetime, timezone, timedelta
from statistics import mean

from supabase import create_client

from app.services.food_category_service import classify_foods_cached

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

# ── Constants ─────────────────────────────────────────────────────────────────

ONSET_WINDOWS     = [30, 60, 120, 240, 480, 720, 1440]  # minutes
WB_DIMENSIONS     = ["energy_level", "mood", "stress_level", "sleep_quality", "sleep_hours"]
MEAL_SLOTS        = ["breakfast", "lunch", "dinner", "snack"]
WB_SLOTS          = ["morning", "midday", "evening"]
MIN_EXPOSED_MEALS   = 3
MIN_UNEXPOSED_MEALS = 5
MIN_WB_SAMPLES      = 3
MIN_RR              = 1.5
MIN_WB_DELTA        = 0.5
RR_MAX              = 5.0

# Wellbeing dimensions where LOWER is better (i.e. less stress = good)
_LOWER_IS_BETTER = {"stress_level"}


# ── Data loading ──────────────────────────────────────────────────────────────

def _load_between(user_id: str, start_iso: str, end_iso: str) -> tuple[list, list, list]:
    """Return (meals, symptoms, wellbeing_snapshots) logged within [start, end]."""
    meals = (
        supabase.table("meals")
        .select("id, foods, logged_at, meal_type")
        .eq("user_id", user_id)
        .gte("logged_at", start_iso)
        .lte("logged_at", end_iso)
        .execute()
    ).data or []

    symptoms = (
        supabase.table("symptoms")
        .select("id, meal_id, logged_at, symptom_type, severity, onset_minutes")
        .eq("user_id", user_id)
        .gte("logged_at", start_iso)
        .lte("logged_at", end_iso)
        .execute()
    ).data or []

    wellbeing = (
        supabase.table("wellbeing_snapshots")
        .select("id, logged_at, period, energy_level, mood, stress_level, sleep_quality, sleep_hours")
        .eq("user_id", user_id)
        .gte("logged_at", start_iso)
        .lte("logged_at", end_iso)
        .execute()
    ).data or []

    return meals, symptoms, wellbeing


def load_data(user_id: str, period_days: int) -> tuple[list, list, list]:
    """Return (meals, symptoms, wellbeing_snapshots) for the trailing window."""
    now = datetime.now(timezone.utc)
    start = (now - timedelta(days=period_days)).isoformat()
    return _load_between(user_id, start, now.isoformat())


# ── Category exposure ─────────────────────────────────────────────────────────

def build_category_exposure(
    meals: list,
    category_map: dict[str, list[str]],
) -> dict[str, set[str]]:
    """Return mapping: category_slug → set of meal IDs that contain it."""
    exposure: dict[str, set[str]] = {}
    for meal in meals:
        foods_raw = meal.get("foods") or []
        for food_item in foods_raw:
            name = (food_item.get("name") or "").strip()
            if not name:
                continue
            for slug in category_map.get(name, []):
                exposure.setdefault(slug, set()).add(meal["id"])
    return exposure


# ── Symptom signals ───────────────────────────────────────────────────────────

def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except (ValueError, AttributeError):
        return None


def _laplace(count: int, n: int) -> float:
    return (count + 0.5) / (n + 1)


def compute_symptom_signals(
    category: str,
    exposed_ids: set[str],
    unexposed_ids: set[str],
    meals: list,
    symptoms: list,
) -> list[dict]:
    """Compute counterfactual relative-risk signals for one food category."""
    if len(exposed_ids) < MIN_EXPOSED_MEALS or len(unexposed_ids) < MIN_UNEXPOSED_MEALS:
        return []

    meal_dt: dict[str, datetime] = {}
    for m in meals:
        dt = _parse_dt(m.get("logged_at"))
        if dt:
            meal_dt[m["id"]] = dt

    # symptom_type → list of (logged_at, meal_id_or_none)
    symptom_types: set[str] = set()
    for s in symptoms:
        st = s.get("symptom_type")
        if st:
            symptom_types.add(st)

    signals: list[dict] = []

    for symptom_type in symptom_types:
        best_rr = 0.0
        best_window = None
        best_evidence = 0

        for window in ONSET_WINDOWS:
            exposed_hits = 0
            for mid in exposed_ids:
                mdt = meal_dt.get(mid)
                if mdt is None:
                    continue
                cutoff = mdt + timedelta(minutes=window)
                for s in symptoms:
                    if s.get("symptom_type") != symptom_type:
                        continue
                    s_dt = _parse_dt(s.get("logged_at"))
                    if s_dt and mdt <= s_dt <= cutoff:
                        exposed_hits += 1
                        break  # one hit per meal

            unexposed_hits = 0
            for mid in unexposed_ids:
                mdt = meal_dt.get(mid)
                if mdt is None:
                    continue
                cutoff = mdt + timedelta(minutes=window)
                for s in symptoms:
                    if s.get("symptom_type") != symptom_type:
                        continue
                    s_dt = _parse_dt(s.get("logged_at"))
                    if s_dt and mdt <= s_dt <= cutoff:
                        unexposed_hits += 1
                        break

            n_exp = len(exposed_ids)
            n_unexp = len(unexposed_ids)
            p_with = _laplace(exposed_hits, n_exp)
            p_without = _laplace(unexposed_hits, n_unexp)
            rr = p_with / p_without

            if rr > best_rr:
                best_rr = rr
                best_window = window
                best_evidence = exposed_hits

        if best_rr >= MIN_RR and best_evidence >= MIN_EXPOSED_MEALS:
            signals.append({
                "category": category,
                "outcome_type": "symptom",
                "outcome_name": symptom_type,
                "direction": "harmful",
                "peak_window_minutes": best_window,
                "meal_slot": None,
                "wellbeing_slot": None,
                "relative_risk": round(best_rr, 3),
                "score_delta": None,
                "evidence_count": best_evidence,
            })

    return signals


# ── Wellbeing signals ─────────────────────────────────────────────────────────

def compute_wellbeing_signals(
    category: str,
    exposed_ids: set[str],
    unexposed_ids: set[str],
    meals: list,
    wellbeing: list,
) -> list[dict]:
    """Compute wellbeing outcome signals for one food category."""
    if len(exposed_ids) < MIN_EXPOSED_MEALS or len(unexposed_ids) < MIN_UNEXPOSED_MEALS:
        return []

    # meal_id → (date, meal_slot)
    meal_info: dict[str, tuple[datetime, str]] = {}
    for m in meals:
        dt = _parse_dt(m.get("logged_at"))
        slot = (m.get("meal_type") or "snack").lower()
        if slot not in MEAL_SLOTS:
            slot = "snack"
        if dt:
            meal_info[m["id"]] = (dt, slot)

    # wellbeing grouped by (date, period)
    wb_by_date_period: dict[tuple, list[dict]] = {}
    for wb in wellbeing:
        dt = _parse_dt(wb.get("logged_at"))
        if dt is None:
            continue
        period = wb.get("period") or _infer_period(dt)
        key = (dt.date(), period)
        wb_by_date_period.setdefault(key, []).append(wb)

    signals: list[dict] = []

    for meal_slot in MEAL_SLOTS:
        for wb_slot in WB_SLOTS:
            for dimension in WB_DIMENSIONS:
                exposed_scores: list[float] = []
                unexposed_scores: list[float] = []

                for mid in exposed_ids | unexposed_ids:
                    info = meal_info.get(mid)
                    if info is None:
                        continue
                    meal_dt, m_slot = info
                    if m_slot != meal_slot:
                        continue

                    scores = _collect_wb_scores(meal_dt, wb_slot, dimension, wb_by_date_period)
                    if mid in exposed_ids:
                        exposed_scores.extend(scores)
                    else:
                        unexposed_scores.extend(scores)

                if len(exposed_scores) < MIN_WB_SAMPLES or len(unexposed_scores) < MIN_WB_SAMPLES:
                    continue

                exp_mean = mean(exposed_scores)
                unexp_mean = mean(unexposed_scores)
                delta = exp_mean - unexp_mean  # positive = exposed scored higher

                if abs(delta) < MIN_WB_DELTA:
                    continue

                # Direction: beneficial when score is higher for "good" dimensions
                if dimension in _LOWER_IS_BETTER:
                    direction = "beneficial" if delta < 0 else "harmful"
                else:
                    direction = "beneficial" if delta > 0 else "harmful"

                signals.append({
                    "category": category,
                    "outcome_type": "wellbeing",
                    "outcome_name": dimension,
                    "direction": direction,
                    "peak_window_minutes": None,
                    "meal_slot": meal_slot,
                    "wellbeing_slot": wb_slot,
                    "relative_risk": None,
                    "score_delta": round(delta, 3),
                    "evidence_count": min(len(exposed_scores), len(unexposed_scores)),
                })

    return signals


def _infer_period(dt: datetime) -> str:
    hour = dt.hour
    if hour < 11:
        return "morning"
    if hour < 16:
        return "midday"
    return "evening"


def _collect_wb_scores(
    meal_dt: datetime,
    wb_slot: str,
    dimension: str,
    wb_by_date_period: dict[tuple, list[dict]],
) -> list[float]:
    """Collect wellbeing dimension scores for a given slot on same/next day."""
    scores: list[float] = []
    for offset in [0, 1]:
        target_date = (meal_dt + timedelta(days=offset)).date()
        key = (target_date, wb_slot)
        for wb in wb_by_date_period.get(key, []):
            val = wb.get(dimension)
            if val is not None:
                scores.append(float(val))
    return scores


# ── Unified score ─────────────────────────────────────────────────────────────

def compute_unified_score(
    symptom_signals: list[dict],
    wellbeing_signals: list[dict],
) -> float:
    """Compute 0–1 unified score combining all signals with convergence bonus."""
    all_signals = symptom_signals + wellbeing_signals
    if not all_signals:
        return 0.0

    normalised: list[float] = []
    for sig in all_signals:
        if sig["outcome_type"] == "symptom" and sig["relative_risk"] is not None:
            rr = sig["relative_risk"]
            normalised.append(min((rr - 1) / (RR_MAX - 1), 1.0))
        elif sig["outcome_type"] == "wellbeing" and sig["score_delta"] is not None:
            normalised.append(min(abs(sig["score_delta"]) / 10.0, 1.0))

    if not normalised:
        return 0.0

    base = max(normalised)

    channels_with_signals = 0
    if symptom_signals:
        channels_with_signals += 1
    if wellbeing_signals:
        channels_with_signals += 1

    multiplier = min(1.0 + 0.2 * (channels_with_signals - 1), 1.4)
    return round(min(base * multiplier, 1.0), 4)


# ── Run analysis ──────────────────────────────────────────────────────────────

def _compute_signals(user_id: str, meals: list, symptoms: list,
                     wellbeing: list) -> list[dict]:
    """Classify foods, build exposure, compute per-category signals. Returns
    signal rows (with user_id, unified_score, analyzed_at) ready to insert. No DB
    writes. Returns [] when there are no meals."""
    if not meals:
        return []

    all_food_names: list[str] = []
    for meal in meals:
        for food_item in (meal.get("foods") or []):
            name = (food_item.get("name") or "").strip().lower()
            if name:
                all_food_names.append(name)

    classification_cache: dict[str, list[str]] = {}
    category_map = classify_foods_cached(list(set(all_food_names)), classification_cache)

    for meal in meals:
        for food_item in (meal.get("foods") or []):
            if food_item.get("name"):
                food_item["name"] = food_item["name"].strip().lower()

    exposure = build_category_exposure(meals, category_map)
    all_meal_ids = {m["id"] for m in meals}
    all_signals: list[dict] = []

    for category, exposed_ids in exposure.items():
        unexposed_ids = all_meal_ids - exposed_ids
        symptom_sigs = compute_symptom_signals(
            category, exposed_ids, unexposed_ids, meals, symptoms
        )
        wellbeing_sigs = compute_wellbeing_signals(
            category, exposed_ids, unexposed_ids, meals, wellbeing
        )
        if not symptom_sigs and not wellbeing_sigs:
            continue
        unified = compute_unified_score(symptom_sigs, wellbeing_sigs)
        analyzed_at = datetime.now(timezone.utc).isoformat()
        for sig in symptom_sigs + wellbeing_sigs:
            sig["unified_score"] = unified
            sig["analyzed_at"] = analyzed_at
            sig["user_id"] = user_id
            all_signals.append(sig)

    return all_signals


def run_analysis(user_id: str, period_days: int = 365) -> dict:
    """Full live analysis: load trailing window → compute → replace food_signals."""
    t0 = time.time()
    meals, symptoms, wellbeing = load_data(user_id, period_days)
    all_signals = _compute_signals(user_id, meals, symptoms, wellbeing)

    supabase.table("food_signals").delete().eq("user_id", user_id).execute()
    if all_signals:
        supabase.table("food_signals").insert(all_signals).execute()

    _update_last_analyzed(user_id)
    return {
        "categories_analysed": len({s["category"] for s in all_signals}),
        "signals_found": len(all_signals),
        "duration_seconds": round(time.time() - t0, 2),
    }


def analyze_year(user_id: str, year: int) -> int:
    """Compute one calendar year's signals and replace that year's frozen rows.
    Returns the number of signal rows written."""
    start = datetime(year, 1, 1, tzinfo=timezone.utc).isoformat()
    end = datetime(year, 12, 31, 23, 59, 59, tzinfo=timezone.utc).isoformat()
    meals, symptoms, wellbeing = _load_between(user_id, start, end)
    signals = _compute_signals(user_id, meals, symptoms, wellbeing)

    rows = [{
        "user_id": user_id,
        "year": year,
        "category": s["category"],
        "outcome_type": s["outcome_type"],
        "outcome_name": s["outcome_name"],
        "direction": s["direction"],
        "unified_score": s.get("unified_score"),
        "relative_risk": s.get("relative_risk"),
        "evidence_count": s.get("evidence_count") or 0,
    } for s in signals]

    supabase.table("food_signals_yearly").delete() \
        .eq("user_id", user_id).eq("year", year).execute()
    if rows:
        supabase.table("food_signals_yearly").insert(rows).execute()
    return len(rows)


def ensure_yearly_backfill(user_id: str, recompute_current: bool = True) -> None:
    """Compute any not-yet-backfilled PAST calendar years once (frozen), and
    recompute the CURRENT year when recompute_current is True.

    A past year is skipped once it has been analyzed, tracked via
    health_profile.yearly_backfilled_years — NOT via the presence of signal rows,
    so a past year that produced zero signals (gap/sparse year) still freezes
    once instead of re-analyzing on every read."""
    current_year = datetime.now(timezone.utc).year

    earliest = (
        supabase.table("meals")
        .select("logged_at")
        .eq("user_id", user_id)
        .order("logged_at")
        .limit(1)
        .execute()
    ).data
    if not earliest:
        return
    first_dt = _parse_dt(earliest[0]["logged_at"])
    if first_dt is None:
        return
    first_year = first_dt.year

    profile = (
        supabase.table("health_profile")
        .select("yearly_backfilled_years")
        .eq("user_id", user_id)
        .maybe_single()
        .execute()
    ).data
    backfilled = set(profile.get("yearly_backfilled_years") or []) if profile else set()

    newly: list[int] = []
    for year in range(first_year, current_year):  # past years only
        if year not in backfilled:
            analyze_year(user_id, year)
            newly.append(year)

    if newly:
        supabase.table("health_profile").upsert(
            {"user_id": user_id,
             "yearly_backfilled_years": sorted(backfilled | set(newly))},
            on_conflict="user_id",
        ).execute()

    if recompute_current:
        analyze_year(user_id, current_year)


def _update_last_analyzed(user_id: str) -> None:
    supabase.table("health_profile").upsert(
        {"user_id": user_id, "last_analyzed_at": datetime.now(timezone.utc).isoformat()},
        on_conflict="user_id",
    ).execute()
