import os
from datetime import datetime, timezone

from fastapi import Depends, HTTPException
from supabase import create_client

from app.auth import get_current_user

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _license_state(user_id: str) -> tuple[str, str | None]:
    """(state, expires_at_iso) — state in active|none|revoked|expired."""
    rows = (
        supabase.table("licenses")
        .select("status,expires_at")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    ).data or []
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
    Depends on get_current_user; FastAPI caches that call within a request so the
    endpoint's own Depends(get_current_user) does not re-hit Supabase auth."""
    state, _ = _license_state(user["id"])
    if state != "active":
        raise HTTPException(status_code=403, detail="no_active_license")
    return user
