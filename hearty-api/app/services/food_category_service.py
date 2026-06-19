"""Food category classification service.

Maps raw food names onto a fixed 18-category taxonomy via a single LLM call.
All 18 slugs are validated on the way out; unknown slugs are dropped.
"""
import json
import os
import re

import litellm

# ── Taxonomy ──────────────────────────────────────────────────────────────────

TAXONOMY: dict[str, dict] = {
    "fodmap_fructans": {
        "display": "FODMAP Fructans",
        "examples": ["garlic", "onion", "leek", "shallots", "wheat", "rye", "barley"],
        "notes": "Wheat overlaps with gluten",
    },
    "fodmap_fructose": {
        "display": "FODMAP Fructose",
        "examples": ["apples", "pears", "honey", "mango", "HFCS"],
        "notes": "Apples/pears also in fodmap_polyols",
    },
    "fodmap_polyols": {
        "display": "FODMAP Polyols",
        "examples": ["stone fruits", "mushrooms", "sorbitol", "xylitol", "mannitol sweeteners"],
        "notes": "Polyol-class only; not sucralose/aspartame",
    },
    "fodmap_gos": {
        "display": "FODMAP GOS (Galacto-oligosaccharides)",
        "examples": ["beans", "lentils", "chickpeas", "whole soy milk"],
        "notes": "Monash FODMAP terminology",
    },
    "fodmap_lactose": {
        "display": "FODMAP Lactose",
        "examples": ["milk", "yogurt", "soft cheese", "ice cream"],
        "notes": "Enzyme deficiency mechanism",
    },
    "dairy_casein": {
        "display": "Dairy / Casein",
        "examples": ["all dairy including butter", "aged cheese", "hard cheese"],
        "notes": "Protein sensitivity; broader than lactose",
    },
    "gluten": {
        "display": "Gluten",
        "examples": ["wheat", "barley", "rye", "spelt"],
        "notes": "Overlaps fodmap_fructans for wheat",
    },
    "eggs": {
        "display": "Eggs",
        "examples": ["egg white", "egg yolk", "whole egg"],
        "notes": "FDA Big-9 allergen",
    },
    "soy": {
        "display": "Soy",
        "examples": ["soy milk", "tofu", "tempeh", "edamame", "soy sauce"],
        "notes": "FDA Big-9; distinct from GOS content",
    },
    "histamine": {
        "display": "High Histamine",
        "examples": ["aged cheese", "red wine", "cured meats", "fermented foods", "tinned fish"],
        "notes": "DAO enzyme pathway",
    },
    "sulfites": {
        "display": "Sulfites",
        "examples": ["dried fruit", "white wine", "shrimp", "deli meats", "vinegar"],
        "notes": "Sulfite oxidase pathway",
    },
    "caffeine": {
        "display": "Caffeine",
        "examples": ["coffee", "tea", "energy drinks", "dark chocolate"],
        "notes": "Dark chocolate also in histamine",
    },
    "alcohol": {
        "display": "Alcohol",
        "examples": ["wine", "beer", "spirits"],
        "notes": "DAO inhibitor; overlaps histamine/sulfites",
    },
    "high_fat": {
        "display": "High Fat",
        "examples": ["fried food", "fatty cuts", "cream sauces", "pastries", "desserts"],
        "notes": "",
    },
    "cruciferous": {
        "display": "Cruciferous Vegetables",
        "examples": ["broccoli", "cauliflower", "cabbage", "brussels sprouts"],
        "notes": "Some GOS overlap",
    },
    "nightshades": {
        "display": "Nightshades",
        "examples": ["tomato", "peppers", "eggplant"],
        "notes": "Provisional/low-evidence; potato excluded",
    },
    "high_sugar_refined": {
        "display": "High Sugar / Refined",
        "examples": ["HFCS drinks", "soda", "candy", "syrups"],
        "notes": "Narrowed; pastries → high_fat",
    },
    "spicy": {
        "display": "Spicy",
        "examples": ["hot peppers", "chilli", "hot sauce"],
        "notes": "TRPV1 mechanism",
    },
}

VALID_SLUGS = set(TAXONOMY.keys())


def category_label(slug: str) -> str:
    """Human-facing label for a category slug. Uses the TAXONOMY display name;
    falls back to a prettified slug for anything unknown. Empty/None -> ''."""
    if not slug:
        return ""
    entry = TAXONOMY.get(slug)
    if entry and entry.get("display"):
        return entry["display"]
    return slug.replace("_", " ").title()

# Known multi-category foods — used as prompt seed hints.
MULTI_CATEGORY_FOODS: dict[str, list[str]] = {
    "wheat": ["gluten", "fodmap_fructans"],
    "bread": ["gluten", "fodmap_fructans"],
    "pasta": ["gluten", "fodmap_fructans"],
    "apples": ["fodmap_fructose", "fodmap_polyols"],
    "pears": ["fodmap_fructose", "fodmap_polyols"],
    "red wine": ["alcohol", "histamine"],
    "white wine": ["alcohol", "sulfites"],
    "dark chocolate": ["caffeine", "histamine"],
    "aged cheese": ["dairy_casein", "histamine"],
    "cured meats": ["histamine", "sulfites"],
    "fermented foods": ["histamine"],
    "deli meats": ["histamine", "sulfites"],
}

# ── Prompt ─────────────────────────────────────────────────────────────────────

_TAXONOMY_SUMMARY = "\n".join(
    f"- {slug}: {info['display']} (e.g. {', '.join(info['examples'][:3])})"
    for slug, info in TAXONOMY.items()
)

_MULTI_HINTS = "\n".join(
    f"- {food}: {cats}" for food, cats in MULTI_CATEGORY_FOODS.items()
)

_CLASSIFY_PROMPT = f"""You are a nutrition classifier. Map each food name to zero or more
of the following 18 category slugs.

CATEGORIES:
{_TAXONOMY_SUMMARY}

MULTI-CATEGORY SEED HINTS (non-exhaustive — use as examples):
{_MULTI_HINTS}

Rules:
- Use only the exact slugs listed above.
- A food may belong to multiple categories; list all that apply.
- If a food clearly belongs to none, return an empty list for it.
- Do not add commentary. Return ONLY valid JSON.

Input: a JSON array of food name strings.
Output format: {{"food_name": ["slug", ...], ...}}

Foods to classify:
{{food_names_json}}
"""


def _strip_code_fence(content: str) -> str:
    content = content.strip()
    if content.startswith("```"):
        content = re.sub(r"^```(?:json)?\s*", "", content)
        content = re.sub(r"\s*```$", "", content)
    return content.strip()


def classify_foods(food_names: list[str]) -> dict[str, list[str]]:
    """Classify a list of food names into taxonomy categories.

    Returns a dict mapping each food name to a list of valid category slugs.
    Unknown foods map to []. Uses a single LLM call for the entire batch.
    """
    if not food_names:
        return {}

    unique_names = list(dict.fromkeys(food_names))  # dedupe, preserve order
    prompt = _CLASSIFY_PROMPT.replace(
        "{food_names_json}", json.dumps(unique_names)
    )

    response = litellm.completion(
        model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
        messages=[{"role": "user", "content": prompt}],
        api_base=os.environ.get("LLM_BASE_URL") or None,
    )
    content = _strip_code_fence(response.choices[0].message.content)

    try:
        raw: dict = json.loads(content)
    except json.JSONDecodeError as e:
        raise ValueError(f"LLM returned non-JSON for food classification: {content}") from e

    result: dict[str, list[str]] = {}
    for name in unique_names:
        # Try exact match first, then case-insensitive fallback
        slugs = raw.get(name) or raw.get(name.lower()) or []
        if not isinstance(slugs, list):
            slugs = []
        # Validate: keep only known slugs
        result[name] = [s for s in slugs if s in VALID_SLUGS]

    return result


def classify_foods_cached(
    food_names: list[str],
    cache: dict[str, list[str]],
) -> dict[str, list[str]]:
    """classify_foods with an external in-memory cache (per-analysis-run dict).

    Already-classified names are read from cache; only new names hit the LLM.
    The cache dict is mutated in-place with new results.
    """
    new_names = [n for n in food_names if n not in cache]
    if new_names:
        new_results = classify_foods(new_names)
        cache.update(new_results)

    return {name: cache.get(name, []) for name in food_names}
