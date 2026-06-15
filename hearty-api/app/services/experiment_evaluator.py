"""Experiment evaluator: baseline-vs-experiment outcome comparison with honest
guardrails. Pure. result dict: verdict, reason, adherence, baseline_rate,
experiment_rate, logged_days."""

import os

ADHERENCE_MIN = float(os.environ.get("EXPERIMENT_ADHERENCE_MIN", "0.7"))
MIN_WINDOW_DAYS = int(os.environ.get("EXPERIMENT_MIN_WINDOW_DAYS", "7"))
IMPROVE_REL_MARGIN = float(os.environ.get("EXPERIMENT_IMPROVE_REL_MARGIN", "0.2"))


def _symptom_rate(symptoms: list, name: str, logged_days: int) -> float:
    if logged_days <= 0:
        return 0.0
    days = {s.get("logged_at", "")[:10] for s in symptoms if s.get("symptom_type") == name}
    return len(days) / logged_days


def _wellbeing_mean(snapshots: list, name: str) -> float:
    vals = [s[name] for s in snapshots if s.get(name) is not None]
    return (sum(vals) / len(vals)) if vals else 0.0


def evaluate(*, outcome_type: str, outcome_name: str,
             baseline_symptoms: list, experiment_symptoms: list,
             baseline_wellbeing: list, experiment_wellbeing: list,
             baseline_logged_days: int, experiment_logged_days: int,
             adherence: dict) -> dict:
    result = {
        "adherence": adherence["adherence"],
        "logged_days": {"baseline": baseline_logged_days,
                        "experiment": experiment_logged_days},
        "baseline_rate": None, "experiment_rate": None,
    }

    if adherence["adherence"] < ADHERENCE_MIN:
        return {**result, "verdict": "inconclusive", "reason": "low_adherence"}
    if (baseline_logged_days < MIN_WINDOW_DAYS
            or experiment_logged_days < MIN_WINDOW_DAYS):
        return {**result, "verdict": "inconclusive", "reason": "thin_data"}

    if outcome_type == "symptom":  # lower is better
        base = _symptom_rate(baseline_symptoms, outcome_name, baseline_logged_days)
        exp = _symptom_rate(experiment_symptoms, outcome_name, experiment_logged_days)
        if base == 0:
            improved = False          # can't improve below an already-zero rate
            worse = exp > 0
        else:
            improved = exp <= base * (1 - IMPROVE_REL_MARGIN)
            worse = exp >= base * (1 + IMPROVE_REL_MARGIN)
    else:  # wellbeing: higher is better
        base = _wellbeing_mean(baseline_wellbeing, outcome_name)
        exp = _wellbeing_mean(experiment_wellbeing, outcome_name)
        if base == 0:
            improved = False          # no baseline to beat -> don't claim improvement
            worse = False
        else:
            improved = exp >= base * (1 + IMPROVE_REL_MARGIN)
            worse = exp <= base * (1 - IMPROVE_REL_MARGIN)

    verdict = "improved" if improved else "worse" if worse else "no_change"
    return {**result, "verdict": verdict, "reason": None,
            "baseline_rate": round(base, 4), "experiment_rate": round(exp, 4)}
