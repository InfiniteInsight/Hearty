import os
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException
from supabase import create_client

from app.auth import get_current_user

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

_DEFAULT_SETTINGS = {"provisioning_mode": "open", "trial_days": 14}


def _get_settings() -> dict:
    """Owner-configured provisioning settings (single row id=1). Falls back to
    defaults if the row is somehow absent."""
    rows = (
        supabase.table("app_settings")
        .select("provisioning_mode,trial_days")
        .eq("id", 1)
        .limit(1)
        .execute()
    ).data or []
    return rows[0] if rows else dict(_DEFAULT_SETTINGS)


def _fetch(user_id: str) -> list[dict]:
    return (
        supabase.table("licenses")
        .select("status,expires_at")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    ).data or []


def _provision(user_id: str, settings: dict | None = None) -> None:
    """Create a license row for a brand-new user per the current provisioning mode.
    No-op for paywall. Idempotent via on_conflict/ignore_duplicates so concurrent
    first-requests can't violate the unique constraint. Accepts pre-read settings
    so the caller can avoid a redundant app_settings query."""
    s = settings or _get_settings()
    mode = s.get("provisioning_mode", "open")
    if mode == "paywall":
        return
    row = {"user_id": user_id, "status": "active"}
    if mode == "trial":
        days = int(s.get("trial_days") or _DEFAULT_SETTINGS["trial_days"])
        row["activation_source"] = "trial"
        row["expires_at"] = (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()
    else:  # open
        row["activation_source"] = "comp"
    supabase.table("licenses").upsert(row, on_conflict="user_id", ignore_duplicates=True).execute()


def _license_state(user_id: str) -> tuple[str, str | None]:
    """(state, expires_at_iso) — state in active|none|revoked|expired.
    Lazily provisions a brand-new user (no row) per the provisioning mode."""
    rows = _fetch(user_id)
    if not rows:
        _provision(user_id, settings=_get_settings())
        rows = _fetch(user_id)
        if not rows:
            return "none", None
    row = rows[0]
    exp = row.get("expires_at")
    if row.get("status") != "active":
        return "revoked", exp
    if exp:
        exp_dt = datetime.fromisoformat(str(exp).replace("Z", "+00:00"))
        if exp_dt.tzinfo is None:
            exp_dt = exp_dt.replace(tzinfo=timezone.utc)
        if exp_dt <= datetime.now(timezone.utc):
            return "expired", exp
    return "active", exp


async def require_active_license(user=Depends(get_current_user)) -> dict:
    """Gate user-facing data routes on an active, non-expired license.
    FastAPI caches get_current_user within a request, so the endpoint's own
    Depends(get_current_user) does not re-hit Supabase auth."""
    state, _ = _license_state(user["id"])
    if state != "active":
        raise HTTPException(status_code=403, detail="no_active_license")
    return user
