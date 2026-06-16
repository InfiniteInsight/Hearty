"""Food-plate vision processor: send a plate photo to Claude (via litellm,
multimodal) and parse the identified-foods JSON array. Pure except for the
litellm call (patched in tests). Identification only — no calorie/macro data
(portion estimates from photos are unreliable; nutrition comes from Spec 07)."""

import base64
import json
import os

import litellm

VISION_MODEL = os.environ.get("VISION_MODEL") or os.environ.get(
    "LLM_MODEL", "claude-sonnet-4-6")

FOOD_PLATE_PROMPT = (
    "You are analyzing a photo of food. Identify every distinct food item "
    "visible on the plate or in the image. For each item, return a JSON array "
    "with this structure:\n"
    '[{"name": "common food name", "portion": "approximate portion description, '
    "e.g. 'approximately 1 fillet' or 'small side portion'\", "
    '"confidence": float between 0 and 1}]\n'
    "If no food is visible, return an empty array. If the items are "
    'indistinguishable (e.g. a stew), return [{"name": "mixed dish", "portion": '
    '"unknown", "confidence": 0.2}]. Do not fabricate ingredients. '
    "Reply with only the JSON array, no prose."
)


def _strip_code_fence(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[1] if "\n" in t else t
        if t.endswith("```"):
            t = t.rsplit("```", 1)[0]
    return t.strip()


def analyze_food_plate(image_bytes: bytes, content_type: str) -> dict:
    b64 = base64.b64encode(image_bytes).decode()
    messages = [{"role": "user", "content": [
        {"type": "text", "text": FOOD_PLATE_PROMPT},
        {"type": "image_url",
         "image_url": {"url": f"data:{content_type};base64,{b64}"}},
    ]}]
    response = litellm.completion(
        model=VISION_MODEL, messages=messages,
        api_base=os.environ.get("LLM_BASE_URL") or None,
    )
    content = _strip_code_fence(response.choices[0].message.content)
    try:
        foods = json.loads(content)
    except json.JSONDecodeError as e:
        raise ValueError(f"Vision returned non-JSON response: {content}") from e
    if not isinstance(foods, list):
        foods = foods.get("foods", []) if isinstance(foods, dict) else []
    return {"foods": foods, "source": "food_plate_vision"}
