"""Signal persistence: annotate live food signals with cross-year recurrence.

Pure logic — given the set of live category slugs and the frozen per-year rows
from food_signals_yearly, derive per-category recurrence/new flags. Keyed at the
category level (matching unified_score's granularity)."""


def compute_persistence(
    live_categories: set[str],
    yearly_rows: list[dict],
    current_year: int,
) -> dict[str, dict]:
    """Return {category: {years_seen, recurring, is_new, strength_by_year}} for
    every category in live_categories.

    - years_seen: sorted years that had a stored (real) signal for the category.
    - recurring: appeared in >= 2 calendar years.
    - is_new: no appearance in any year before current_year.
    - strength_by_year: {str(year): max unified_score that year} (JSON-friendly keys).
    """
    by_cat: dict[str, dict] = {}
    for r in yearly_rows:
        cat = r["category"]
        year = int(r["year"])
        score = float(r["unified_score"]) if r.get("unified_score") is not None else 0.0
        d = by_cat.setdefault(cat, {"years": set(), "strength": {}})
        d["years"].add(year)
        d["strength"][year] = max(d["strength"].get(year, 0.0), score)

    out: dict[str, dict] = {}
    for cat in live_categories:
        d = by_cat.get(cat)
        years = sorted(d["years"]) if d else []
        is_new = not any(y < current_year for y in years)  # True also when years == []
        out[cat] = {
            "years_seen": years,
            "recurring": len(years) >= 2,
            "is_new": is_new,
            "strength_by_year": {str(y): d["strength"][y] for y in years} if d else {},
        }
    return out


def compute_resolved(
    yearly_rows: list[dict],
    live_categories: set[str],
    feedback: list[dict],
    current_year: int,
) -> list[dict]:
    """Categories that had a signal LAST calendar year but are absent from the
    current live set. status='resolved' if the user confirmed it (signal_feedback
    verdict='confirmed'), else 'potentially_resolved'. Sorted by last-year
    strength, descending."""
    last_year = current_year - 1
    last_year_strength: dict[str, float] = {}
    for r in yearly_rows:
        if int(r["year"]) == last_year:
            cat = r["category"]
            score = float(r["unified_score"]) if r.get("unified_score") is not None else 0.0
            last_year_strength[cat] = max(last_year_strength.get(cat, 0.0), score)

    confirmed = {f["category"] for f in feedback if f.get("verdict") == "confirmed"}

    out = []
    for cat, strength in last_year_strength.items():
        if cat in live_categories:
            continue  # still active — not resolved
        out.append({
            "category": cat,
            "last_year": last_year,
            "strength": strength,
            "status": "resolved" if cat in confirmed else "potentially_resolved",
        })
    out.sort(key=lambda r: r["strength"], reverse=True)
    return out
