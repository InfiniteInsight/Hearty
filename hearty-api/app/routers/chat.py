import logging
import os
from datetime import datetime, timezone
from typing import Literal, Optional

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

_MEAL_CLARIFICATION_RULES_BASE = """
Your job has two steps: (1) get a clear enough meal description, (2) learn how the user is feeling. Only ask for what you don't already have, and only if it genuinely matters.

STEP 1 — Is the meal description clear enough to log?

It IS clear enough when any of these are true:
- A brand name is present — brand already identifies the product as commercial; origin and type are known.
- The user listed specific ingredients they combined — clearly homemade and specific enough.
- The user said "homemade" explicitly.
- It's a named item from a named chain or restaurant (e.g. "Big Mac", "Chipotle burrito bowl").
- It's a simple, unambiguous whole food (e.g. apple, banana, hard-boiled egg, glass of milk).
- The food type is specific enough that origin wouldn't meaningfully change its nutritional character (e.g. coffee, green tea, water).

It is NOT clear enough when:
- It's a packaged/commercial food category with no brand named (e.g. "a protein bar", "an energy drink", "a granola bar") — ask for the brand (and flavor if not already mentioned), since nutrition varies widely by product.
- Origin is genuinely ambiguous AND would significantly change what was eaten (e.g. "a burrito", "a sandwich", "pizza") — homemade vs. a restaurant vs. a frozen brand are very different meals.
- The description is too vague to log at all (e.g. "a snack", "some food", "I ate something").

If not clear enough: ask ONE question covering only the missing piece — never ask for information the user already gave.

STEP 2 — Have they said how they're feeling?

Look at everything the user has said in this conversation:
- If they reported a symptom or discomfort but gave no severity rating → ask them to rate it 1–10.
- If they reported a symptom or discomfort AND already gave a number → respond and close.
- If they said they feel fine, good, normal, or similar → that's complete; close without asking for a number.
- If they haven't mentioned how they're feeling at all → ask how they're feeling after eating and invite a 1–10 rating, e.g. "How are you feeling after eating? Any discomfort on a scale of 1–10?" If they reply with "fine" or "good" or similar, that's complete — don't push for a number.

READING THE CONVERSATION STATE

Check Hearty's most recent message before responding:
- Hearty last asked a meal clarification question → the user is answering it. After their answer, go to Step 2. If feelings haven't been covered yet, ask now. Do NOT close early.
- Hearty last asked how they're feeling → the user is answering that. Apply Step 2 rules and close. Ask nothing else.
- This is the first message in the conversation → run Step 1 then Step 2 in order."""

_ALWAYS_WARM = "ALWAYS: One question per turn. Under 2 sentences. Warm but concise. Never repeat a question already answered. When closing, end with a brief warm statement — not a question."
_ALWAYS_CONCISE = "ALWAYS: One question per turn. Under 2 sentences. Never repeat a question already answered. When closing, confirm with one short statement."

_OFF_TOPIC_WARM = 'If the message is not about food, eating, symptoms, or wellbeing, decline warmly in one sentence and redirect, e.g. "I\'m just a food and health journal — I can\'t help with that, but I can log what you ate or how you\'re feeling."'
_OFF_TOPIC_CONCISE = 'If the message is not about food, eating, symptoms, or wellbeing, decline in one sentence and redirect, e.g. "I\'m just a food and health journal — I can\'t help with that, but I can log what you ate or how you\'re feeling."'


def _make_system_prompt(signal_context: Optional[str], style: str) -> str:
    if style == "concise":
        preamble = (
            "You are Hearty, a health and food journal assistant.\n"
            "The user is logging what they ate or how they're feeling.\n"
            "Do not comment on the user's food choices, lifestyle, or emotional state. "
            "When they report symptoms or wellbeing, log without adding commentary or empathy."
        )
        always = _ALWAYS_CONCISE
        off_topic = _OFF_TOPIC_CONCISE
    else:
        preamble = (
            "You are Hearty, a friendly health and food journal assistant.\n"
            "The user is logging what they ate or how they're feeling.\n"
            "When they describe symptoms or wellbeing, respond with brief empathy."
        )
        always = _ALWAYS_WARM
        off_topic = _OFF_TOPIC_WARM

    parts = [preamble, _MEAL_CLARIFICATION_RULES_BASE, always, off_topic]
    if signal_context:
        parts.append(signal_context)
    return "\n".join(parts)


class ChatRequest(BaseModel):
    message: str
    health_context: Optional[dict] = None
    logged_at: Optional[datetime] = None
    meal_id: Optional[str] = None
    history: Optional[list[dict]] = None
    conversation_style: Literal['warm', 'concise'] = 'warm'


class ChatResponse(BaseModel):
    reply: str
    meal_id: Optional[str] = None


_JOURNAL_PREFIXES = (
    'i ate', 'i had', 'i drank', "i'm eating", "i'm having",
    "i'm feeling", 'i feel', "i've been", 'i just', 'i noticed',
)
_STRIP_PREFIXES = ('can you ', 'could you ', 'would you ')
_STARTS_WITH_BLOCKED = (
    'who ', 'what ', 'where ', 'why ',
    'when did ', 'when is ', 'when was ', 'when are ',
    'how do ', 'how can ', 'how would ', 'how to ', 'how does ',
    'tell me', 'explain', 'help me with',
    'write me', 'write a', 'draft',
    'call ', 'play ', 'text ',
)
_ANYWHERE_BLOCKED = (
    'weather', 'news', 'music', 'sports', 'stock', 'remind',
    'homework', 'movie', 'film', 'joke', 'trivia', 'calculate',
    'find me', 'look up', 'search for', 'teach me',
    'show me how', 'set a timer', 'set a reminder',
)


def _is_off_topic(message: str) -> bool:
    t = message.lower().strip()
    if any(t.startswith(p) for p in _JOURNAL_PREFIXES):
        return False
    if t.endswith('?'):
        return True
    for p in _STRIP_PREFIXES:
        if t.startswith(p):
            t = t[len(p):]
            break
    if any(t.startswith(p) for p in _STARTS_WITH_BLOCKED):
        return True
    if any(p in t for p in _ANYWHERE_BLOCKED):
        return True
    return False


@router.post("/api/chat", status_code=200)
async def chat(
    body: ChatRequest,
    user=Depends(get_current_user),
) -> ChatResponse:
    # Reject off-topic messages before touching the database.
    if not body.meal_id and _is_off_topic(body.message):
        return ChatResponse(
            reply="I'm just a food and health journal — I can't help with that, but I can log what you ate or how you're feeling.",
            meal_id=None,
        )

    # Log the message as a meal entry in the background (best-effort).
    meal_id: Optional[str] = body.meal_id

    if meal_id:
        # ── Follow-up turn: symptom response OR meal clarification ────────────
        # Extract symptoms first to determine intent before touching the meal.
        # Build a context string from the last few turns so the extractor can
        # resolve bare ratings ("about a 7") back to the symptom they refer to.
        symptoms = []
        try:
            recent_turns = (body.history or [])[-4:]
            if recent_turns:
                ctx_lines = [
                    f"{'Hearty' if m['role'] == 'assistant' else 'User'}: {m['content']}"
                    for m in recent_turns
                ]
                ctx_lines.append(f"User: {body.message}")
                extraction_input = "\n".join(ctx_lines)
            else:
                extraction_input = body.message
            symptoms = ai_extraction.extract_symptoms(extraction_input)
        except Exception as e:
            logger.error("Follow-up symptom extraction failed: %s", e, exc_info=True)

        # Only insert when we have at least one symptom with a confirmed severity.
        # If severity is null the AI will ask for a 1-10 rating; the next turn
        # carries the full context so we log once with complete data then.
        symptoms_ready = [s for s in symptoms if s.get("severity") is not None]

        if symptoms and not symptoms_ready:
            pass  # symptoms found but no severity yet — wait for the rating turn
        elif symptoms_ready:
            # Feelings/symptom response — log symptoms, do NOT update the meal
            try:
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
                    for s in symptoms_ready
                ]
                rows = [{k: v for k, v in r.items() if v is not None} for r in rows]
                supabase.table("symptoms").insert(rows).execute()
            except Exception as e:
                logger.error("Follow-up symptom insert failed: %s", e, exc_info=True)
        else:
            # Meal clarification — update meal using ALL user messages for accuracy
            try:
                user_messages = [
                    m["content"] for m in (body.history or []) if m.get("role") == "user"
                ]
                combined = " ".join(user_messages + [body.message]) if user_messages else body.message

                try:
                    extracted = ai_extraction.extract_meal(combined)
                    foods = extracted.get("foods") or None
                    inferred_meal_type = extracted.get("inferred_meal_type")
                    normalized_description = extracted.get("normalized_description")
                except Exception as extract_err:
                    logger.warning("Follow-up meal extraction failed: %s", extract_err)
                    foods = None
                    inferred_meal_type = None
                    normalized_description = None

                updates: dict = {"description": normalized_description or combined}
                if foods is not None:
                    updates["foods"] = foods
                if inferred_meal_type:
                    updates["meal_type"] = inferred_meal_type

                supabase.table("meals").update(updates).eq("id", meal_id).eq(
                    "user_id", user["id"]
                ).execute()
            except Exception as e:
                logger.error("Follow-up meal update failed: %s", e, exc_info=True)

    else:
        # ── First turn: insert new meal ────────────────────────────────────────
        try:
            foods = None
            inferred_meal_type = None
            normalized_description = None
            try:
                extracted = ai_extraction.extract_meal(body.message)
                foods = extracted.get("foods") or None
                inferred_meal_type = extracted.get("inferred_meal_type")
                normalized_description = extracted.get("normalized_description")
            except Exception as extract_err:
                logger.warning("Meal extraction failed (inserting raw): %s", extract_err)

            row = {
                "user_id": user["id"],
                "description": normalized_description or body.message,
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
    system_prompt = _make_system_prompt(signal_context, body.conversation_style or "warm")

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
