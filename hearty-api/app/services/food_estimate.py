"""Tier 4: Claude estimates nutrition from a free-text description. Always
returns a result (never cached); on parse failure returns a zero-confidence
null estimate so the orchestrator can still surface the ai_estimate caveat."""

import json
import os

import litellm

FOOD_LLM_MODEL = os.environ.get("FOOD_LLM_MODEL") or os.environ.get(
    "LLM_MODEL", "claude-sonnet-4-6")

_ESTIMATE_PROMPT = (
    "Estimate the nutritional content for the following food item. Return JSON "
    "only, no prose: {{\"calories\": int, \"protein_g\": num, \"total_carbs_g\": "
    "num, \"total_fat_g\": num, \"confidence\": float between 0 and 1}}. Base your "
    "estimate on typical preparation and standard portion sizes. If you cannot "
    "make a reasonable estimate, set all numeric fields to null and confidence to "
    "0.\n\nFood item: {description}"
)


def _strip_fence(t: str) -> str:
    t = t.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[1] if "\n" in t else t
        if t.endswith("```"):
            t = t.rsplit("```", 1)[0]
    return t.strip()


def ai_estimate(description: str) -> dict:
    resp = litellm.completion(
        model=FOOD_LLM_MODEL,
        messages=[{"role": "user",
                   "content": _ESTIMATE_PROMPT.format(description=description)}],
        api_base=os.environ.get("LLM_BASE_URL") or None)
    content = _strip_fence(resp.choices[0].message.content or "")
    try:
        data = json.loads(content)
    except (TypeError, ValueError):
        data = {"calories": None, "protein_g": None, "total_carbs_g": None,
                "total_fat_g": None, "confidence": 0.0}
    return {"item_name": description, "calories": data.get("calories"),
            "protein_g": data.get("protein_g"),
            "total_carbs_g": data.get("total_carbs_g"),
            "total_fat_g": data.get("total_fat_g"),
            "confidence": data.get("confidence") if data.get("confidence") is not None else 0.0,
            "source": "ai_estimate", "tier": 4}
