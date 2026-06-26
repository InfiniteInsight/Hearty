"""Server-side prompt overlays (Spec 11 Layer 3).

Owner-editable 'guidance' text layered onto the locked core prompts of Hearty's
AI surfaces. Reads are best-effort: any error or missing row yields '' so a
storage hiccup can never break an AI call. Writes append a version for
history/revert.
"""

import logging
import os
from datetime import datetime, timezone

from supabase import create_client

logger = logging.getLogger(__name__)
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

SURFACES = ("summary", "trends_conversation")


def get_overlay(surface: str) -> str:
    """Current guidance overlay for a surface. Best-effort: '' on missing/error."""
    try:
        rows = (supabase.table("prompt_overlays")
                .select("guidance").eq("surface", surface).limit(1)
                .execute()).data or []
        return (rows[0].get("guidance") or "") if rows else ""
    except Exception as e:  # never break the AI call this augments
        logger.error("get_overlay(%s) failed: %s", surface, e, exc_info=True)
        return ""


def list_overlays() -> list[dict]:
    return (supabase.table("prompt_overlays")
            .select("surface, guidance, updated_at")
            .execute()).data or []


def set_overlay(surface: str, guidance: str, admin_id) -> dict:
    """Update the current overlay AND append a history version. Raises ValueError
    on an unknown surface."""
    if surface not in SURFACES:
        raise ValueError(f"unknown surface: {surface}")
    supabase.table("prompt_overlay_versions").insert(
        {"surface": surface, "guidance": guidance, "created_by": admin_id}).execute()
    res = (supabase.table("prompt_overlays")
           .update({"guidance": guidance,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                    "updated_by": admin_id})
           .eq("surface", surface).execute())
    return res.data[0] if res.data else {}


def list_versions(surface: str) -> list[dict]:
    return (supabase.table("prompt_overlay_versions")
            .select("id, surface, guidance, created_at, created_by")
            .eq("surface", surface)
            .order("created_at", desc=True)
            .execute()).data or []


def revert(surface: str, version_id, admin_id) -> dict:
    """Re-apply an old version's guidance as a NEW save (forward history)."""
    # Scope the lookup to the surface too, so a version_id from another surface
    # can't be reverted onto this one (returns no row -> "version not found").
    rows = (supabase.table("prompt_overlay_versions")
            .select("guidance").eq("id", version_id).eq("surface", surface).limit(1)
            .execute()).data or []
    if not rows:
        raise ValueError("version not found")
    return set_overlay(surface, rows[0]["guidance"], admin_id)
