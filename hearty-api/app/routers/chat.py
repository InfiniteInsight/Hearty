import os
from datetime import datetime, timezone
from typing import Optional

import litellm
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from supabase import create_client

from app.auth import get_current_user
from app.services import ai_extraction

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

_MODEL = os.getenv("LLM_MODEL", "claude-sonnet-4-6")

SYSTEM_PROMPT = """You are Hearty, a friendly health and food journal assistant.
The user is logging what they ate or how they're feeling.
When they describe a meal, acknowledge it warmly and ask how they're feeling.
When they describe symptoms or wellbeing, respond with brief empathy.
Keep all responses under 2 sentences. Be warm but concise."""


class ChatRequest(BaseModel):
    message: str
    health_context: Optional[dict] = None


class ChatResponse(BaseModel):
    reply: str


@router.post("/api/chat", status_code=200)
async def chat(
    body: ChatRequest,
    user=Depends(get_current_user),
) -> ChatResponse:
    # Log the message as a meal entry in the background (best-effort).
    try:
        extracted = ai_extraction.extract_meal(body.message)
        foods = extracted.get("foods", [])
        inferred_meal_type = extracted.get("inferred_meal_type")
        row = {
            "user_id": user["id"],
            "description": body.message,
            "meal_type": inferred_meal_type,
            "foods": foods,
            "logged_at": datetime.now(timezone.utc).isoformat(),
            "input_method": "voice",
        }
        row = {k: v for k, v in row.items() if v is not None}
        supabase.table("meals").insert(row).execute()
    except Exception:
        pass  # meal logging failure must not break the chat response

    # Generate conversational reply.
    try:
        messages = [{"role": "user", "content": body.message}]
        response = litellm.completion(
            model=_MODEL,
            messages=messages,
            system=SYSTEM_PROMPT,
            max_tokens=100,
        )
        reply = response.choices[0].message.content or "Got it! How are you feeling?"
    except Exception:
        reply = f'Got it! I logged "{body.message}". How are you feeling?'

    return ChatResponse(reply=reply)
