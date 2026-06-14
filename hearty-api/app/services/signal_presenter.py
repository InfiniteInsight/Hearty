"""Signal presenter: apply the user's feedback overlay to raw food_signals
and rank them for the monthly trends conversation. Pure logic — DB access is
isolated in load_presented_signals()."""

import os
from datetime import datetime, timezone

from app.models.schemas import PresentedSignal
from app.services import signal_persistence

# A disputed signal only resurfaces if its unified_score has grown by at least
# this much beyond the score at the time of dispute.
RESURFACE_MARGIN = float(os.environ.get("TRENDS_RESURFACE_MARGIN", "0.20"))


def _key(d: dict) -> tuple:
    return (d["category"], d["outcome_type"], d["outcome_name"])


def apply_overlay(
    signals: list[dict],
    feedback: list[dict],
    previously_surfaced: set[tuple],
) -> list[PresentedSignal]:
    """Filter + annotate + rank.

    - disputed: suppressed, unless current unified_score exceeds score_at_verdict
      by >= RESURFACE_MARGIN (then surfaced with is_resurfaced=True)
    - confirmed: kept, is_confirmed=True
    - snoozed / none: kept as-is
    - is_new: signal identity not in previously_surfaced
    Ranked by unified_score descending.
    """
    fb_by_key = {_key(f): f for f in feedback}
    presented: list[PresentedSignal] = []

    for s in signals:
        k = _key(s)
        fb = fb_by_key.get(k)
        is_confirmed = False
        is_resurfaced = False

        if fb is not None:
            verdict = fb["verdict"]
            if verdict == "disputed":
                prior = fb.get("score_at_verdict") or 0.0
                if float(s["unified_score"]) - float(prior) >= RESURFACE_MARGIN:
                    is_resurfaced = True
                else:
                    continue  # suppressed
            elif verdict == "confirmed":
                is_confirmed = True
            # snoozed → no change

        presented.append(PresentedSignal(
            category=s["category"],
            outcome_type=s["outcome_type"],
            outcome_name=s["outcome_name"],
            direction=s["direction"],
            unified_score=float(s["unified_score"]),
            relative_risk=(float(s["relative_risk"])
                           if s.get("relative_risk") is not None else None),
            evidence_count=int(s.get("evidence_count") or 0),
            is_new=(k not in previously_surfaced),
            is_confirmed=is_confirmed,
            is_resurfaced=is_resurfaced,
        ))

    presented.sort(key=lambda p: p.unified_score, reverse=True)
    return presented


def load_presented_signals(supabase, user_id: str) -> list[PresentedSignal]:
    """Load food_signals + signal_feedback for a user and apply the overlay.

    `previously_surfaced` is derived from signal_feedback identities: any signal
    the user has ever given a verdict on has, by definition, been surfaced. This
    is a pragmatic proxy for v1 (no separate surfaced-log table)."""
    signals = (
        supabase.table("food_signals")
        .select("category, outcome_type, outcome_name, direction, "
                "unified_score, relative_risk, evidence_count")
        .eq("user_id", user_id)
        .execute()
    ).data or []

    feedback = (
        supabase.table("signal_feedback")
        .select("category, outcome_type, outcome_name, verdict, score_at_verdict")
        .eq("user_id", user_id)
        .execute()
    ).data or []

    previously_surfaced = {_key(f) for f in feedback}
    presented = apply_overlay(signals, feedback, previously_surfaced)

    # Attach cross-year recurrence (years_seen + recurring) from the frozen
    # per-year sets. Only those two fields — PresentedSignal.is_new keeps the
    # overlay's "never-verdicted" meaning, distinct from calendar-year newness.
    yearly_rows = (
        supabase.table("food_signals_yearly")
        .select("category, year, outcome_type, outcome_name, unified_score")
        .eq("user_id", user_id)
        .execute()
    ).data or []
    persistence = signal_persistence.compute_persistence(
        {p.category for p in presented}, yearly_rows,
        current_year=datetime.now(timezone.utc).year,
    )
    return [
        p.model_copy(update={
            "years_seen": persistence.get(p.category, {}).get("years_seen", []),
            "recurring": persistence.get(p.category, {}).get("recurring", False),
        })
        for p in presented
    ]
