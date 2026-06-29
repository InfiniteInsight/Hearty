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
      "preparation": "cooking method or null",
      "confidence": number_between_0_and_1
    }
  ],
  "inferred_meal_type": "breakfast|lunch|dinner|snack|drink|supplement|other"
}

normalized_description should be a clean, concise meal label — not a transcript of what the user said.
confidence is your certainty (0-1) that you correctly identified this food from the description; lower it when the wording was ambiguous or misspelled.
Be conservative with calorie estimates — omit them rather than guess wildly.
If the description is not actually about food or drink (e.g. an unrelated sentence, a test phrase, a question, or only a symptom/feeling with no food mentioned), return an empty "foods" array and an empty string for "normalized_description". Do NOT invent a food.
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
      "symptom_type": "one of: acid_reflux|bloating|gas|nausea|urgency|loose_stool|constipation|stomach_pain|cramping|fatigue|brain_fog|headache|skin_reaction|heart_palpitations|indigestion|upset_stomach|sour_stomach|gut_rot|other",
      "severity": 1-10_or_null,  // use the EXACT number the user states — do not round, adjust, or convert between scales
      "onset_minutes": number_or_null,
      "duration_minutes": number_or_null,
      "bathroom_urgency": 0-5_or_null,
      "bathroom_visits": number_or_null,
      "stool_consistency": 1-7_or_null
    }
  ]
}

Type selection guidance:
- acid_reflux: burning, reflux, heartburn, hot sensation in stomach/chest/throat, or sour stomach where burning/acid taste is dominant
- stomach_pain: general ache, soreness, or diffuse abdominal pain — "my stomach hurts", "stomachache", "tummy ache"
- cramping: sharp, gripping, or wave-like abdominal pain — "stomach cramps", "cramps"
- bloating: fullness, pressure, or distension — "too full", "feel bloated", "belly feels tight"
- gas: flatulence, gassy, burping, belching, rumbling
- nausea: queasy, nauseous, urge to vomit — "feeling sick", "feel like I might throw up"
- urgency: sudden strong need to use the bathroom
- indigestion: general post-meal digestive discomfort without dominant burning or cramping — "indigestion", "dyspepsia", "digestion is off"
- upset_stomach: general stomach upset without a clear dominant feature — "upset stomach", "stomach is bothering me"
- sour_stomach: sour or acidic stomach feeling — "sour stomach", "acidic feeling", "stomach feels sour"
- gut_rot: intense post-meal digestive distress — "gut rot", "my gut is wrecked"

Colloquial aliases:
- "heartburn" → acid_reflux
- "feeling sick to my stomach" → nausea
- "stomach flu" / "stomach bug" → extract the symptoms described (nausea, loose_stool, cramping), do not use "other"
- "gassy" → gas
- "too full" / "uncomfortably full" → bloating

Extract multiple symptoms if the description mentions more than one.
Do not diagnose. Extract only what is stated.

If the description does NOT report any actual symptom, discomfort, or negative
physical/mental feeling — e.g. a positive or neutral statement like "feeling
good", "I'm great", "fine", "no issues", "all good", or unrelated text — return
an empty "symptoms" array. Do NOT invent symptoms and do NOT treat positive or
neutral feelings as symptoms.

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


def generate_summary(stats: dict, health_context: str = "",
                     research_context: str = "", style_overlay: str = "") -> str:
    """Generate a natural language summary from aggregated health stats.

    When ``health_context``/``research_context`` are non-empty they are appended
    (health first, then research) so the summary accounts for the user's profile
    and any retrieved research. Empty contexts leave the prompt byte-identical to
    the no-context path.
    """
    prompt = SUMMARY_PROMPT.replace("{stats_json}", json.dumps(stats))
    if style_overlay:
        prompt = f"{prompt}\n\n{style_overlay}"
    if health_context:
        prompt = f"{prompt}\n\n{health_context}"
    if research_context:
        prompt = f"{prompt}\n\n{research_context}"
    response = litellm.completion(
        model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
        messages=[{"role": "user", "content": prompt}],
        api_base=os.environ.get("LLM_BASE_URL") or None,
    )
    return response.choices[0].message.content
