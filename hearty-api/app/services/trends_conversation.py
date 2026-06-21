"""Trends conversation engine: turn the user's presented signals into a warm,
plain-language back-and-forth. Pure with respect to voice — it knows nothing
about STT/TTS. One litellm call per turn, same pattern as ai_extraction."""

import json
import os

import litellm

from app.models.schemas import (
    PresentedSignal, ConversationTurn, ProposedVerdict, ProposedExperiment,
    TrendsConversationResponse,
)
from app.services.ai_extraction import _strip_code_fence
from app.services.food_category_service import category_label


def _signal_line(s: PresentedSignal) -> str:
    tags = []
    if s.is_new:
        tags.append("NEW")
    if s.is_confirmed:
        tags.append("CONFIRMED")
    if s.is_resurfaced:
        tags.append("RESURFACED-STRONGER")
    if s.recurring:
        tags.append(f"RECURRING {len(s.years_seen)} years")
    tag = f" [{', '.join(tags)}]" if tags else ""
    rr = f", relative risk {s.relative_risk:.1f}x" if s.relative_risk else ""
    return (f"- {s.category} → {s.outcome_name} ({s.direction}, "
            f"strength {s.unified_score:.2f}{rr}, "
            f"{s.evidence_count} data points){tag}")


def build_system_prompt(signals: list[PresentedSignal],
                        health_context: str = "") -> str:
    signal_block = "\n".join(_signal_line(s) for s in signals) or "(no signals)"
    prompt = f"""You are Hearty, a warm, plain-spoken food-and-symptom companion \
having a brief monthly check-in conversation with the user about the patterns \
in their data. Speak naturally and kindly. No clinical jargon, no alarmism, no \
medical claims — these are observed correlations, not diagnoses.

This month's patterns (ranked strongest first):
{signal_block}

How to run the conversation:
- Open with the single strongest, most useful pattern (the "headline").
- Let the user steer; answer their questions grounded ONLY in the patterns above.
- CONFIRMED patterns: mention briefly as established; do not re-litigate them.
- RECURRING patterns (seen across multiple years) are the most trustworthy — \
lean on that as a confidence cue ("this has come up several years running"). \
Do not overstate; they remain observed correlations, not diagnoses.
- Coverage rule: before you finish, make sure every pattern above has been \
raised at least once ("Before we finish, there are a couple more I noticed…").
- When the user clearly expresses a verdict on a pattern (e.g. "that's right" / \
"dairy's fine for me, that's wrong" / "not sure"), propose the matching verdict \
for their confirmation — never assume it is final.
- For a HARMFUL pattern the user seems interested in, you may offer a 2-week \
elimination experiment via proposed_experiment (the same category/outcome as \
that pattern) — never start it silently; the app shows a confirm chip.
- When every pattern has been covered and there is nothing left to raise, set \
is_closing to true and give a short, finite goodbye.

Respond with ONLY a JSON object, no prose around it:
{{
  "reply": "what you say to the user this turn",
  "proposed_verdict": null OR {{"category": "...", "outcome_type": "symptom|wellbeing", "outcome_name": "...", "verdict": "confirmed|disputed|snoozed"}},
  "proposed_experiment": null OR {{"category": "...", "outcome_type": "symptom|wellbeing", "outcome_name": "..."}},
  "is_closing": false
}}
proposed_verdict and proposed_experiment must each reference one of the exact \
patterns above, or be null."""
    if health_context:
        prompt = f"{prompt}\n\n{health_context}"
    return prompt


def generate_turn(
    signals: list[PresentedSignal],
    history: list[ConversationTurn],
    health_context: str = "",
) -> TrendsConversationResponse:
    messages = [{"role": "system",
                 "content": build_system_prompt(signals, health_context)}]
    for turn in history:
        messages.append({"role": turn.role, "content": turn.content})
    if not history:
        messages.append({"role": "user",
                         "content": "Start the check-in with the headline pattern."})

    response = litellm.completion(
        model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
        messages=messages,
        api_base=os.environ.get("LLM_BASE_URL") or None,
    )
    content = _strip_code_fence(response.choices[0].message.content)
    data = json.loads(content)

    pv = data.get("proposed_verdict")
    proposed = (
        ProposedVerdict(**pv, category_label=category_label(pv["category"]))
        if pv else None
    )
    pe = data.get("proposed_experiment")
    proposed_exp = (
        ProposedExperiment(**pe, category_label=category_label(pe["category"]))
        if pe else None
    )
    return TrendsConversationResponse(
        reply=data["reply"],
        proposed_verdict=proposed,
        proposed_experiment=proposed_exp,
        is_closing=bool(data.get("is_closing", False)),
    )
