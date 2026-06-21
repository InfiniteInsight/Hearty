"""Health-profile context injection (Spec 08 Phase 4, §9.1).

Turns a user's health profile into a system-prompt block that downstream AI
prompts (trends/summary analysis) inject as context. No behaviour change yet —
this module only formats and loads; callers wire it in later tasks.

NOTE: The MCP Server's ``get_health_profile`` tool (Spec 02) should also call
``build_health_profile_context`` to build its session-context block. That wiring
lives in the MCP Server and is not implemented here.
"""

import os
from datetime import datetime, timezone

from supabase import create_client

from app.health_profile.schemas import HealthProfileResponse

# Own module-level client (mirrors the router's service-key client) so callers
# can load a profile without importing the router, and so tests can monkeypatch
# ``context.supabase`` directly.
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _format_allergen_listing(profile: HealthProfileResponse) -> str:
    parts = []
    for a in profile.allergens:
        if a.confirmed_by_doctor:
            parts.append(f"{a.name} ({a.severity.value}, confirmed)")
        else:
            parts.append(f"{a.name} ({a.severity.value})")
    return ", ".join(parts)


def _format_intolerance_listing(profile: HealthProfileResponse) -> str:
    parts = []
    for i in profile.intolerances:
        if i.threshold:
            parts.append(f"{i.name} ({i.threshold})")
        else:
            parts.append(i.name)
    return ", ".join(parts)


def _format_condition_listing(profile: HealthProfileResponse) -> str:
    parts = []
    for c in profile.conditions:
        if c.diagnosis_year:
            parts.append(f"{c.name} (diagnosed {c.diagnosis_year})")
        else:
            parts.append(c.name)
    return ", ".join(parts)


def _active_protocols(profile: HealthProfileResponse) -> list:
    return [p for p in profile.dietary_protocols if p.active]


def _format_protocol_listing(profile: HealthProfileResponse) -> str:
    parts = []
    for p in _active_protocols(profile):
        if p.phase and p.started:
            parts.append(f"{p.name} {p.phase} phase (started {p.started})")
        elif p.started:
            parts.append(f"{p.name} (started {p.started})")
        elif p.phase:
            parts.append(f"{p.name} {p.phase} phase")
        else:
            parts.append(p.name)
    return ", ".join(parts)


def _analysis_bullets(profile: HealthProfileResponse) -> list[str]:
    """Analysis instructions relevant to what's present.

    Sourced from §9.1 worked example plus §3.2 / §5.1 / §6.1. Emitted in a
    fixed order: allergens → FODMAP protocol → conditions (GERD, IBS) — matching
    the §9.1 example, which is NOT the same as the listing order.
    """
    bullets: list[str] = []

    # Allergens present → flag any meal containing them. (§3.2 / §9.1; the §9.1
    # example joins allergen names with " or ".)
    if profile.allergens:
        names = " or ".join(a.name for a in profile.allergens)
        bullets.append(
            f"Flag any meal containing {names} regardless of symptom presence"
        )

    active = _active_protocols(profile)

    # Low-FODMAP protocol present → cross-reference FODMAP content. (§6.1 / §9.1)
    if any("fodmap" in p.name.lower() for p in active):
        bullets.append("Cross-reference logged foods against FODMAP content")

    # Gluten-free protocol → treat gluten grains as allergen-level flags. (§6.1)
    if any("gluten-free" in p.name.lower() for p in active):
        bullets.append(
            "Treat wheat, barley, and rye as allergen-level flags and watch for "
            "cross-contamination"
        )

    # Elimination diet → track reintroduced foods. (§6.1)
    if any("elimination diet" in p.name.lower() for p in active):
        bullets.append(
            "Track reintroduced foods and watch for symptom spikes after "
            "reintroduction events"
        )

    # Conditions, in §9.1 example order: GERD before IBS.
    gerd = next((c for c in profile.conditions if "gerd" in c.name.lower()), None)
    if gerd is not None:
        bullets.append("Note acid-triggering foods for GERD relevance")

    ibs = next((c for c in profile.conditions if "ibs" in c.name.lower()), None)
    if ibs is not None:
        bullets.append(
            f"Use {ibs.name} context when interpreting bathroom urgency and "
            "stool consistency patterns"
        )

    # Celiac disease → gluten exposure is high-priority. (§5.1)
    celiac = next((c for c in profile.conditions if "celiac" in c.name.lower()), None)
    if celiac is not None:
        bullets.append(
            "Treat any gluten exposure as high-priority and flag ambiguous "
            "ingredients (sauces, marinades)"
        )

    # Histamine intolerance → flag aged/fermented foods. (§5.1)
    histamine = next(
        (c for c in profile.conditions if "histamine" in c.name.lower()), None
    )
    if histamine is not None:
        bullets.append(
            "Flag aged cheeses, fermented foods, alcohol, and reheated leftovers "
            "for histamine relevance"
        )

    return bullets


def build_health_profile_context(profile: HealthProfileResponse) -> str:
    """Render a health profile as a system-prompt block (Spec 08 §9.1).

    Returns ``""`` when all four domains are empty.
    """
    active_protocols = _active_protocols(profile)
    if not (
        profile.allergens
        or profile.intolerances
        or profile.conditions
        or active_protocols
    ):
        return ""

    listing_lines = ["User health profile:"]
    if profile.allergens:
        listing_lines.append(f"- Allergens: {_format_allergen_listing(profile)}")
    if profile.intolerances:
        listing_lines.append(f"- Intolerances: {_format_intolerance_listing(profile)}")
    if profile.conditions:
        listing_lines.append(f"- Conditions: {_format_condition_listing(profile)}")
    if active_protocols:
        listing_lines.append(
            f"- Dietary protocols: {_format_protocol_listing(profile)}"
        )

    lines = list(listing_lines)
    analysis = _analysis_bullets(profile)
    if analysis:
        lines.append("")
        lines.append("When analyzing meals and symptoms:")
        lines.extend(f"- {b}" for b in analysis)

    return "\n".join(lines)


def _row_to_response(row: dict) -> HealthProfileResponse:
    # Replicated from router._row_to_response to avoid importing the router
    # (and its import-time client) into this module.
    return HealthProfileResponse(
        allergens=row.get("allergens") or [],
        intolerances=row.get("intolerances") or [],
        conditions=row.get("conditions") or [],
        dietary_protocols=row.get("dietary_protocols") or [],
        updated_at=row.get("updated_at") or datetime.now(timezone.utc),
    )


def load_health_profile_context(user_id: str) -> str:
    """Load a user's health profile and render it as a context block.

    Returns ``""`` when the user has no profile row.
    """
    result = (
        supabase.table("health_profile")
        .select("*")
        .eq("user_id", user_id)
        .execute()
    )
    if not result.data:
        return ""
    return build_health_profile_context(_row_to_response(result.data[0]))
