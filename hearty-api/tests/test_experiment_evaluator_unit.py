from datetime import datetime, timezone
from app.services.experiment_evaluator import evaluate


def _sym(day, name="bloating"):
    return {"logged_at": datetime(2026, 6, day, 14, tzinfo=timezone.utc).isoformat(),
            "symptom_type": name}


def _wb(day, energy):
    return {"logged_at": datetime(2026, 6, day, 9, tzinfo=timezone.utc).isoformat(),
            "energy_level": energy}


def _good_adherence():
    return {"clean_days": 12, "logged_days": 13, "adherence": 0.92}


def test_low_adherence_is_inconclusive():
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=[_sym(1)], experiment_symptoms=[],
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence={"clean_days": 4, "logged_days": 10, "adherence": 0.4})
    assert out["verdict"] == "inconclusive"
    assert out["reason"] == "low_adherence"


def test_thin_data_is_inconclusive():
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=[], experiment_symptoms=[],
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=3, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "inconclusive"
    assert out["reason"] == "thin_data"


def test_symptom_dropped_is_improved():
    # baseline: bloating on 6 of 10 days; experiment: 1 of 10
    base = [_sym(d) for d in range(1, 7)]
    exp = [_sym(20)]
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=base, experiment_symptoms=exp,
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "improved"
    assert out["baseline_rate"] > out["experiment_rate"]


def test_symptom_unchanged_is_no_change():
    base = [_sym(d) for d in range(1, 6)]
    exp = [_sym(d) for d in range(15, 20)]
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=base, experiment_symptoms=exp,
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "no_change"


def test_wellbeing_rose_is_improved():
    base = [_wb(d, 4) for d in range(1, 8)]
    exp = [_wb(d, 8) for d in range(15, 22)]
    out = evaluate(outcome_type="wellbeing", outcome_name="energy_level",
                   baseline_symptoms=[], experiment_symptoms=[],
                   baseline_wellbeing=base, experiment_wellbeing=exp,
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "improved"
    assert out["experiment_rate"] > out["baseline_rate"]


def test_symptom_zero_baseline_zero_experiment_is_no_change():
    # No symptoms before AND none during -> the experiment didn't "improve" anything.
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=[], experiment_symptoms=[],
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "no_change"


def test_symptom_zero_baseline_with_experiment_symptoms_is_worse():
    # None before, some during -> worse, not improved.
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=[], experiment_symptoms=[_sym(d) for d in range(15, 20)],
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "worse"


def test_wellbeing_empty_baseline_is_not_falsely_improved():
    # No baseline wellbeing data -> cannot claim improvement; must NOT be 'improved'.
    out = evaluate(outcome_type="wellbeing", outcome_name="energy_level",
                   baseline_symptoms=[], experiment_symptoms=[],
                   baseline_wellbeing=[], experiment_wellbeing=[_wb(d, 8) for d in range(15, 22)],
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] != "improved"
