"""LLM-assisted USDA FoodData Central resolver. Search candidates → ask the LLM to
pick the best generic-food match → fetch that food's full nutrition. Fully
best-effort: any failure (no key, no candidates, LLM/HTTP error, no match) → None."""

import json
import logging
import os
import re

import litellm

from app.services.food_sources import fdc_search, fdc_detail

logger = logging.getLogger(__name__)


def _select(query: str, candidates: list[dict]) -> int | None:
    listing = "\n".join(f"{i}. {c['description']}" for i, c in enumerate(candidates))
    prompt = (
        f"A user logged eating: \"{query}\".\n"
        f"From the USDA entries below, choose the ONE that is the same food in its "
        f"plain/raw/generic form. Avoid processed variants (powder, flour, bread, "
        f"croissant, lunchmeat, chips) and different foods. If none truly match, choose none.\n\n"
        f"{listing}\n\n"
        f'Reply with ONLY a JSON object: {{"index": <number>}} for the best match, '
        f'or {{"index": null}} if none match.'
    )
    resp = litellm.completion(
        model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
        messages=[{"role": "user", "content": prompt}],
        api_base=os.environ.get("LLM_BASE_URL") or None,
        max_tokens=20,
    )
    content = resp.choices[0].message.content or ""
    m = re.search(r"\{.*\}", content, re.S)
    if not m:
        return None
    idx = json.loads(m.group(0)).get("index")
    if isinstance(idx, int) and 0 <= idx < len(candidates):
        return idx
    return None


def resolve(query: str) -> dict | None:
    """Normalized USDA nutrition for the best generic match to `query`, or None."""
    try:
        candidates = fdc_search(query)
        if not candidates:
            return None
        idx = _select(query, candidates)
        if idx is None:
            return None
        return fdc_detail(candidates[idx]["fdc_id"])
    except Exception as e:  # fully best-effort — never raises into the lookup pipeline
        logger.warning("fdc_resolve failed for %r: %s", query, e)
        return None
