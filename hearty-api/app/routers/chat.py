import logging
import os
from datetime import datetime, timezone
from typing import Optional

import litellm
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from supabase import create_client

from app.auth import get_current_user
from app.services import ai_extraction

logger = logging.getLogger(__name__)

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

_MODEL = os.getenv("LLM_MODEL", "claude-sonnet-4-6")

_SIGNAL_SYSTEM_PROMPT_TEMPLATE = """You are Hearty, a friendly health and food journal assistant.
The user is logging what they ate or how they're feeling.

When they describe a meal:
- If the description is vague or missing a key detail needed to log it accurately (e.g. only a category like "protein bar" or "snack" with no brand or specifics), ask ONE short clarifying question — the single most useful missing detail.
- If the description is reasonably specific, acknowledge it warmly and ask how they're feeling — and invite them to rate any discomfort 1–10.

When they describe symptoms or wellbeing, respond with brief empathy.
Keep all responses under 2 sentences. Be warm but concise. Never ask more than one question.

{signal_context}"""

_BASE_SYSTEM_PROMPT = """You are Hearty, a friendly health and food journal assistant.
The user is logging what they ate or how they're feeling.

When they describe a meal:
- If the description is vague or missing a key detail needed to log it accurately (e.g. only a category like "protein bar" or "snack" with no brand or specifics), ask ONE short clarifying question — the single most useful missing detail.
- If the description is reasonably specific, acknowledge it warmly and ask how they're feeling — and invite them to rate any discomfort 1–10.

When they describe symptoms or wellbeing, respond with brief empathy.
Keep all responses under 2 sentences. Be warm but concise. Never ask more than one question."""


class ChatRequest(BaseModel):
    message: str
    health_context: Optional[dict] = None
    logged_at: Optional[datetime] = None
    meal_id: Optional[str] = None
    history: Optional[list[dict]] = None


class ChatResponse(BaseModel):
    reply: str
    meal_id: Optional[str] = None


@router.post("/api/chat", status_code=200)
async def chat(
    body: ChatRequest,
    user=Depends(get_current_user),
) -> ChatResponse:
    # Log the message as a meal entry in the background (best-effort).
    meal_id: Optional[str] = body.meal_id

    if meal_id:
        # ── Follow-up turn: update existing meal, maybe log symptoms ──────────
        try:
            # Build combined description from original user message + follow-up
            original = next(
                (m["content"] for m in (body.history or []) if m.get("role") == "user"),
                "",
            )
            combined = f"{original}. {body.message}" if original else body.message

            # Re-extract and update the meal row
            try:
                extracted = ai_extraction.extract_meal(combined)
                foods = extracted.get("foods") or None
                inferred_meal_type = extracted.get("inferred_meal_type")
            except Exception as extract_err:
                logger.warning("Follow-up meal extraction failed: %s", extract_err)
                foods = None
                inferred_meal_type = None

            updates: dict = {"description": combined}
            if foods is not None:
                updates["foods"] = foods
            if inferred_meal_type:
                updates["meal_type"] = inferred_meal_type

            supabase.table("meals").update(updates).eq("id", meal_id).eq(
                "user_id", user["id"]
            ).execute()
        except Exception as e:
            logger.error("Follow-up meal update failed: %s", e, exc_info=True)

        # Try to extract and log symptoms from the follow-up text
        try:
            symptoms = ai_extraction.extract_symptoms(body.message)
            if symptoms:
                rows = [
                    {
                        "user_id": user["id"],
                        "symptom_type": s.get("symptom_type", "other"),
                        "severity": s.get("severity"),
                        "onset_minutes": s.get("onset_minutes"),
                        "duration_minutes": s.get("duration_minutes"),
                        "bathroom_urgency": s.get("bathroom_urgency"),
                        "bathroom_visits": s.get("bathroom_visits"),
                        "stool_consistency": s.get("stool_consistency"),
                        "raw_description": body.message,
                        "logged_at": datetime.now(timezone.utc).isoformat(),
                    }
                    for s in symptoms
                ]
                rows = [{k: v for k, v in r.items() if v is not None} for r in rows]
                supabase.table("symptom_logs").insert(rows).execute()
        except Exception as e:
            logger.error("Follow-up symptom extraction failed: %s", e, exc_info=True)

    else:
        # ── First turn: insert new meal ────────────────────────────────────────
        try:
            foods = None
            inferred_meal_type = None
            try:
                extracted = ai_extraction.extract_meal(body.message)
                foods = extracted.get("foods") or None
                inferred_meal_type = extracted.get("inferred_meal_type")
            except Exception as extract_err:
                logger.warning("Meal extraction failed (inserting raw): %s", extract_err)

            row = {
                "user_id": user["id"],
                "description": body.message,
                "meal_type": inferred_meal_type,
                "foods": foods,
                "logged_at": (body.logged_at or datetime.now(timezone.utc)).isoformat(),
                "input_method": "voice",
            }
            row = {k: v for k, v in row.items() if v is not None}
            result = supabase.table("meals").insert(row).execute()
            meal_id = result.data[0]["id"] if result.data else None
            logger.info("Meal inserted: %s", result.data)
        except Exception as e:
            logger.error("Meal insert failed: %s", e, exc_info=True)

    # Build health context from top food signals.
    signal_context = _build_signal_context(user["id"])
    if signal_context:
        system_prompt = _SIGNAL_SYSTEM_PROMPT_TEMPLATE.replace(
            "{signal_context}", signal_context
        )
    else:
        system_prompt = _BASE_SYSTEM_PROMPT

    # Generate conversational reply.
    try:
        lm_messages: list[dict] = []
        if body.history:
            lm_messages.extend(body.history)
        lm_messages.append({"role": "user", "content": body.message})
        response = litellm.completion(
            model=_MODEL,
            messages=lm_messages,
            system=system_prompt,
            max_tokens=100,
        )
        reply = response.choices[0].message.content or "Got it! How are you feeling?"
    except Exception:
        reply = f'Got it! I logged "{body.message}". How are you feeling?'

    return ChatResponse(reply=reply, meal_id=meal_id)


def _build_signal_context(user_id: str) -> str:
    """Return a natural-language summary of the user's top food signals for the system prompt."""
    try:
        rows = (
            supabase.table("food_signals")
            .select("category, outcome_type, outcome_name, direction, peak_window_minutes, meal_slot, wellbeing_slot, relative_risk, score_delta, unified_score")
            .eq("user_id", user_id)
            .order("unified_score", desc=True)
            .limit(5)
            .execute()
        ).data or []
    except Exception:
        return ""

    if not rows:
        return ""

    from app.services.food_category_service import TAXONOMY

    lines: list[str] = []
    # Group by category for a cleaner summary
    by_category: dict[str, list] = {}
    for row in rows:
        by_category.setdefault(row["category"], []).append(row)

    for category, category_rows in list(by_category.items())[:5]:
        display = TAXONOMY.get(category, {}).get("display", category.replace("_", " ").title())
        parts: list[str] = []
        for r in category_rows:
            outcome = r["outcome_name"].replace("_", " ")
            direction = r["direction"]
            if r["outcome_type"] == "symptom" and r.get("relative_risk"):
                window = r.get("peak_window_minutes")
                win_str = f" {window//60}–{(window*2)//60}h" if window else ""
                parts.append(f"{outcome}{win_str} (RR {r['relative_risk']:.1f}×, {direction})")
            elif r["outcome_type"] == "wellbeing" and r.get("score_delta") is not None:
                delta = r["score_delta"]
                parts.append(f"{outcome} {'+' if delta > 0 else ''}{delta:.1f} pts ({direction})")

        if parts:
            lines.append(f"- {display}: {'; '.join(parts)}")

    if not lines:
        return ""

    return "Known food signals for this user:\n" + "\n".join(lines)
