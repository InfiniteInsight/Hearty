import os
import time
import litellm
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from supabase import create_client

from app.auth import get_current_admin
from app.services import knowledge

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _effective_status(row: dict) -> str:
    """The status the gate actually sees: an 'active' row past its expiry reads
    as 'expired' (the stored status stays 'active'). Keeps the admin table honest
    about who currently has access."""
    status = row.get("status")
    exp = row.get("expires_at")
    if status == "active" and exp:
        exp_dt = datetime.fromisoformat(str(exp).replace("Z", "+00:00"))
        if exp_dt.tzinfo is None:
            exp_dt = exp_dt.replace(tzinfo=timezone.utc)
        if exp_dt <= datetime.now(timezone.utc):
            return "expired"
    return status


def _parse_ts(ts):
    return datetime.fromisoformat(str(ts).replace("Z", "+00:00")) if ts else None


def _llm_status(row: dict | None) -> dict:
    """Derive LLM health from the service_health row: ok / degraded / idle."""
    row = row or {}
    ok_at, err_at = row.get("llm_last_ok_at"), row.get("llm_last_error_at")
    out = {"last_ok_at": ok_at, "last_error_at": err_at, "last_error": None,
           "model": row.get("llm_last_model")}
    if not ok_at and not err_at:
        out["status"] = "idle"
        return out
    okd, errd = _parse_ts(ok_at), _parse_ts(err_at)
    if errd and (not okd or errd > okd):
        out["status"] = "degraded"
        out["last_error"] = row.get("llm_last_error")
    else:
        out["status"] = "ok"
    return out


class GrantRequest(BaseModel):
    user_id: str
    expires_at: str | None = None
    tier: str | None = None
    notes: str | None = None


class UpdateRequest(BaseModel):
    expires_at: str | None = None
    tier: str | None = None
    status: str | None = None
    notes: str | None = None


class SettingsUpdate(BaseModel):
    provisioning_mode: str | None = None
    trial_days: int | None = None


class KnowledgeCreate(BaseModel):
    title: str | None = None
    content: str
    conditions: list[str] = []
    source: str = "manual"


class KnowledgeActive(BaseModel):
    active: bool


@router.get("/api/admin/users")
async def list_users(admin=Depends(get_current_admin)) -> dict:
    users = supabase.auth.admin.list_users()
    rows = supabase.table("licenses").select("*").execute().data or []
    by_user = {r["user_id"]: r for r in rows}
    out = []
    for u in users:
        lr = by_user.get(u.id)
        out.append({
            "user_id": u.id,
            "email": u.email,
            "created_at": str(getattr(u, "created_at", "")),
            "license": ({
                "status": _effective_status(lr), "expires_at": lr.get("expires_at"),
                "tier": lr.get("tier"), "activation_source": lr.get("activation_source"),
            } if lr else None),
        })
    return {"users": out}


@router.post("/api/admin/licenses")
async def grant(body: GrantRequest, admin=Depends(get_current_admin)) -> dict:
    row = {
        "user_id": body.user_id, "status": "active",
        "expires_at": body.expires_at, "tier": body.tier,
        "activation_source": "manual", "granted_by": admin["id"],
        "notes": body.notes, "updated_at": _now(),
    }
    row = {k: v for k, v in row.items() if v is not None}
    return supabase.table("licenses").upsert(row, on_conflict="user_id").execute().data[0]


@router.patch("/api/admin/licenses/{user_id}")
async def update(user_id: str, body: UpdateRequest, admin=Depends(get_current_admin)) -> dict:
    updates = {k: v for k, v in {
        "expires_at": body.expires_at, "tier": body.tier,
        "status": body.status, "notes": body.notes,
    }.items() if v is not None}
    updates["updated_at"] = _now()
    res = supabase.table("licenses").update(updates).eq("user_id", user_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="license not found")
    return res.data[0]


@router.post("/api/admin/licenses/{user_id}/revoke")
async def revoke(user_id: str, admin=Depends(get_current_admin)) -> dict:
    res = supabase.table("licenses").update({"status": "revoked", "updated_at": _now()}).eq("user_id", user_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="license not found")
    return res.data[0]


@router.post("/api/admin/licenses/{user_id}/reactivate")
async def reactivate(user_id: str, admin=Depends(get_current_admin)) -> dict:
    res = supabase.table("licenses").update({"status": "active", "updated_at": _now()}).eq("user_id", user_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="license not found")
    return res.data[0]


@router.get("/api/admin/settings")
async def get_settings(admin=Depends(get_current_admin)) -> dict:
    rows = (
        supabase.table("app_settings")
        .select("provisioning_mode,trial_days")
        .eq("id", 1)
        .limit(1)
        .execute()
    ).data or []
    return rows[0] if rows else {"provisioning_mode": "open", "trial_days": 14}


@router.put("/api/admin/settings")
async def update_settings(body: SettingsUpdate, admin=Depends(get_current_admin)) -> dict:
    updates: dict = {}
    if body.provisioning_mode is not None:
        if body.provisioning_mode not in ("open", "trial", "paywall"):
            raise HTTPException(status_code=400, detail="invalid provisioning_mode")
        updates["provisioning_mode"] = body.provisioning_mode
    if body.trial_days is not None:
        if not 0 < body.trial_days <= 3650:
            raise HTTPException(status_code=400, detail="trial_days must be between 1 and 3650")
        updates["trial_days"] = body.trial_days
    updates["updated_at"] = _now()
    updates["updated_by"] = admin["id"]
    res = supabase.table("app_settings").update(updates).eq("id", 1).execute()
    if not res.data:
        raise HTTPException(status_code=500, detail="settings row missing")
    return res.data[0]


@router.get("/api/admin/health")
async def health(admin=Depends(get_current_admin)) -> dict:
    backend = {"status": "ok", "version": "1.0.0",
               "revision": os.environ.get("K_REVISION", "local"), "time": _now()}
    t0 = time.monotonic()
    try:
        rows = supabase.table("service_health").select("*").eq("id", 1).limit(1).execute().data or []
        sb = {"status": "ok", "latency_ms": round((time.monotonic() - t0) * 1000)}
        llm = _llm_status(rows[0] if rows else None)
    except Exception as e:  # dependency down must not 500 the health check
        sb = {"status": "down", "error": str(e)[:300]}
        llm = _llm_status(None)
    return {"backend": backend, "supabase": sb, "llm": llm}


@router.post("/api/admin/health/llm-test")
async def llm_test(admin=Depends(get_current_admin)) -> dict:
    model = os.environ.get("LLM_MODEL", "claude-sonnet-4-6")
    t0 = time.monotonic()
    try:
        litellm.completion(model=model, messages=[{"role": "user", "content": "ping"}], max_tokens=1)
        return {"ok": True, "model": model, "latency_ms": round((time.monotonic() - t0) * 1000)}
    except Exception as e:  # the global callback records the failure; report it cleanly
        return {"ok": False, "model": model, "error": str(e)[:300]}


@router.post("/api/admin/knowledge")
async def add_knowledge(body: KnowledgeCreate, admin=Depends(get_current_admin)) -> dict:
    try:
        return knowledge.add_entry(
            title=body.title, content=body.content,
            conditions=body.conditions, source=body.source)
    except Exception as e:  # embedding/insert failure — tell the owner cleanly
        raise HTTPException(status_code=502, detail=f"embedding failed: {str(e)[:200]}")


@router.get("/api/admin/knowledge")
async def list_knowledge(admin=Depends(get_current_admin)) -> dict:
    return {"entries": knowledge.list_entries()}


@router.delete("/api/admin/knowledge/{entry_id}")
async def delete_knowledge(entry_id: str, admin=Depends(get_current_admin)) -> dict:
    # Intentionally idempotent (no 404 on a missing id, unlike the license
    # endpoints): this is an owner-only curation panel, so deleting an
    # already-gone entry should succeed quietly rather than error.
    knowledge.delete_entry(entry_id)
    return {"ok": True}


@router.patch("/api/admin/knowledge/{entry_id}")
async def patch_knowledge(entry_id: str, body: KnowledgeActive,
                          admin=Depends(get_current_admin)) -> dict:
    return knowledge.set_active(entry_id, body.active)
