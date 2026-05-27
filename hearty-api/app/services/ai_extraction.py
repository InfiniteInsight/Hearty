import json
import os
import re
import litellm


def _strip_code_fence(content: str) -> str:
    content = content.strip()
    if content.startswith("```"):
        content = re.sub(r"^```(?:json)?\s*", "", content)
        content = re.sub(r"\s*```$", "", content)
    return content.strip()

MEAL_EXTRACTION_PROMPT = """
You are a precise food data extractor. Given a natural language meal description,
extract a structured list of food items.

Return ONLY valid JSON with this shape:
{
  "normalized_description": "concise natural-language summary, e.g. 'Quest Cookies and Cream protein bar' or 'homemade pasta with salmon, green onion, and basil'",
  "foods": [
    {
      "name": "food item name",
      "quantity": "serving size or null",
      "estimated_calories": number_or_null,
      "preparation": "cooking method or null"
    }
  ],
  "inferred_meal_type": "breakfast|lunch|dinner|snack|drink|supplement|other"
}

normalized_description should be a clean, concise meal label — not a transcript of what the user said.
Be conservative with calorie estimates — omit them rather than guess wildly.
Do not add commentary. Return only the JSON object.

Description:
{description}
"""

SYMPTOM_EXTRACTION_PROMPT = """
You are a medical data extractor specializing in GI and systemic symptoms.
Given a natural language symptom description, extract structured symptom records.

Return ONLY valid JSON with this shape:
{
  "symptoms": [
    {
      "symptom_type": "one of: acid_reflux|bloating|gas|nausea|urgency|loose_stool|constipation|stomach_pain|cramping|fatigue|brain_fog|headache|skin_reaction|heart_palpitations|other",
      "severity": 1-10_or_null,
      "onset_minutes": number_or_null,
      "duration_minutes": number_or_null,
      "bathroom_urgency": 0-5_or_null,
      "bathroom_visits": number_or_null,
      "stool_consistency": 1-7_or_null
    }
  ]
}

Extract multiple symptoms if the description mentions more than one.
Do not diagnose. Extract only what is stated.
Return only the JSON object.

Description:
{raw_description}
"""

SUMMARY_PROMPT = """
You are Hearty, a personal health journal assistant.
Given the following health data statistics for a user, write a concise,
warm, and informative health summary in 3–5 sentences.

Focus on: notable patterns, symptom frequency, best days, and any
correlations visible in the data.

Never diagnose. Never recommend medications. Clearly frame correlations
as observations, not medical conclusions.

Data:
{stats_json}
"""


def extract_meal(description: str) -> dict:
    """Parse free-form meal description into structured foods list."""
    prompt = MEAL_EXTRACTION_PROMPT.replace("{description}", description)
    response = litellm.completion(
        model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
        messages=[{"role": "user", "content": prompt}],
        api_base=os.environ.get("LLM_BASE_URL") or None,
    )
    content = _strip_code_fence(response.choices[0].message.content)
    try:
        return json.loads(content)
    except json.JSONDecodeError as e:
        raise ValueError(f"AI returned non-JSON response: {content}") from e


def extract_symptoms(raw_description: str) -> list[dict]:
    """Parse free-form symptom description into structured symptom list."""
    prompt = SYMPTOM_EXTRACTION_PROMPT.replace("{raw_description}", raw_description)
    response = litellm.completion(
        model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
        messages=[{"role": "user", "content": prompt}],
        api_base=os.environ.get("LLM_BASE_URL") or None,
    )
    content = _strip_code_fence(response.choices[0].message.content)
    try:
        result = json.loads(content)
        if isinstance(result, list):
            return result
        return result.get("symptoms", result)
    except json.JSONDecodeError as e:
        raise ValueError(f"AI returned non-JSON response: {content}") from e


def generate_summary(stats: dict) -> str:
    """Generate a natural language summary from aggregated health stats."""
    prompt = SUMMARY_PROMPT.replace("{stats_json}", json.dumps(stats))
    response = litellm.completion(
        model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
        messages=[{"role": "user", "content": prompt}],
        api_base=os.environ.get("LLM_BASE_URL") or None,
    )
    return response.choices[0].message.content
