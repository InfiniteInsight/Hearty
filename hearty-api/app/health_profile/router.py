import os
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from supabase import create_client

from app.auth import get_current_user
from app.health_profile.schemas import (
    AllergenEntry,
    AllergensUpdateRequest,
    ConditionEntry,
    ConditionsUpdateRequest,
    DietaryProtocolEntry,
    DietaryProtocolsUpdateRequest,
    HealthProfilePatchRequest,
    HealthProfilePutRequest,
    HealthProfileResponse,
    IntoleranceEntry,
    IntolerancesUpdateRequest,
)

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _get_or_create_row(user_id: str) -> dict:
    result = supabase.table("health_profile").select("*").eq("user_id", user_id).execute()
    if result.data:
        return result.data[0]
    row = {
        "user_id": user_id,
        "allergens": [],
        "intolerances": [],
        "conditions": [],
        "dietary_protocols": [],
        "updated_at": _now_iso(),
    }
    created = supabase.table("health_profile").upsert(row, on_conflict="user_id").execute()
    return created.data[0]


def _row_to_response(row: dict) -> HealthProfileResponse:
    return HealthProfileResponse(
        allergens=row.get("allergens") or [],
        intolerances=row.get("intolerances") or [],
        conditions=row.get("conditions") or [],
        dietary_protocols=row.get("dietary_protocols") or [],
        updated_at=row.get("updated_at") or datetime.now(timezone.utc),
    )


# ── Top-level profile endpoints ──────────────────────────────────────────────

@router.get("/api/health-profile", tags=["health-profile"])
async def get_health_profile(user=Depends(get_current_user)) -> HealthProfileResponse:
    row = _get_or_create_row(user["id"])
    return _row_to_response(row)


@router.put("/api/health-profile", tags=["health-profile"])
async def put_health_profile(
    body: HealthProfilePutRequest,
    user=Depends(get_current_user),
) -> HealthProfileResponse:
    data = {
        "user_id": user["id"],
        "allergens": [e.model_dump() for e in body.allergens],
        "intolerances": [e.model_dump() for e in body.intolerances],
        "conditions": [e.model_dump() for e in body.conditions],
        "dietary_protocols": [e.model_dump() for e in body.dietary_protocols],
        "updated_at": _now_iso(),
    }
    result = supabase.table("health_profile").upsert(data, on_conflict="user_id").execute()
    return _row_to_response(result.data[0])


@router.patch("/api/health-profile", tags=["health-profile"])
async def patch_health_profile(
    body: HealthProfilePatchRequest,
    user=Depends(get_current_user),
) -> HealthProfileResponse:
    row = _get_or_create_row(user["id"])
    data = {
        "user_id": user["id"],
        "allergens": row.get("allergens") or [],
        "intolerances": row.get("intolerances") or [],
        "conditions": row.get("conditions") or [],
        "dietary_protocols": row.get("dietary_protocols") or [],
        "updated_at": _now_iso(),
    }
    if body.allergens is not None:
        data["allergens"] = [e.model_dump() for e in body.allergens]
    if body.intolerances is not None:
        data["intolerances"] = [e.model_dump() for e in body.intolerances]
    if body.conditions is not None:
        data["conditions"] = [e.model_dump() for e in body.conditions]
    if body.dietary_protocols is not None:
        data["dietary_protocols"] = [e.model_dump() for e in body.dietary_protocols]
    result = supabase.table("health_profile").upsert(data, on_conflict="user_id").execute()
    return _row_to_response(result.data[0])


@router.delete("/api/health-profile", tags=["health-profile"])
async def delete_health_profile(user=Depends(get_current_user)) -> HealthProfileResponse:
    data = {
        "user_id": user["id"],
        "allergens": [],
        "intolerances": [],
        "conditions": [],
        "dietary_protocols": [],
        "updated_at": _now_iso(),
    }
    result = supabase.table("health_profile").upsert(data, on_conflict="user_id").execute()
    return _row_to_response(result.data[0])


# ── Sub-resource endpoints ────────────────────────────────────────────────────

@router.get("/api/health-profile/allergens", tags=["health-profile"])
async def get_allergens(user=Depends(get_current_user)) -> list[AllergenEntry]:
    row = _get_or_create_row(user["id"])
    return [AllergenEntry(**e) for e in (row.get("allergens") or [])]


@router.put("/api/health-profile/allergens", tags=["health-profile"])
async def put_allergens(
    body: AllergensUpdateRequest,
    user=Depends(get_current_user),
) -> HealthProfileResponse:
    row = _get_or_create_row(user["id"])
    data = {
        "user_id": user["id"],
        "allergens": [e.model_dump() for e in body.allergens],
        "intolerances": row.get("intolerances") or [],
        "conditions": row.get("conditions") or [],
        "dietary_protocols": row.get("dietary_protocols") or [],
        "updated_at": _now_iso(),
    }
    result = supabase.table("health_profile").upsert(data, on_conflict="user_id").execute()
    return _row_to_response(result.data[0])


@router.get("/api/health-profile/intolerances", tags=["health-profile"])
async def get_intolerances(user=Depends(get_current_user)) -> list[IntoleranceEntry]:
    row = _get_or_create_row(user["id"])
    return [IntoleranceEntry(**e) for e in (row.get("intolerances") or [])]


@router.put("/api/health-profile/intolerances", tags=["health-profile"])
async def put_intolerances(
    body: IntolerancesUpdateRequest,
    user=Depends(get_current_user),
) -> HealthProfileResponse:
    row = _get_or_create_row(user["id"])
    data = {
        "user_id": user["id"],
        "allergens": row.get("allergens") or [],
        "intolerances": [e.model_dump() for e in body.intolerances],
        "conditions": row.get("conditions") or [],
        "dietary_protocols": row.get("dietary_protocols") or [],
        "updated_at": _now_iso(),
    }
    result = supabase.table("health_profile").upsert(data, on_conflict="user_id").execute()
    return _row_to_response(result.data[0])


@router.get("/api/health-profile/conditions", tags=["health-profile"])
async def get_conditions(user=Depends(get_current_user)) -> list[ConditionEntry]:
    row = _get_or_create_row(user["id"])
    return [ConditionEntry(**e) for e in (row.get("conditions") or [])]


@router.put("/api/health-profile/conditions", tags=["health-profile"])
async def put_conditions(
    body: ConditionsUpdateRequest,
    user=Depends(get_current_user),
) -> HealthProfileResponse:
    row = _get_or_create_row(user["id"])
    data = {
        "user_id": user["id"],
        "allergens": row.get("allergens") or [],
        "intolerances": row.get("intolerances") or [],
        "conditions": [e.model_dump() for e in body.conditions],
        "dietary_protocols": row.get("dietary_protocols") or [],
        "updated_at": _now_iso(),
    }
    result = supabase.table("health_profile").upsert(data, on_conflict="user_id").execute()
    return _row_to_response(result.data[0])


@router.get("/api/health-profile/dietary-protocols", tags=["health-profile"])
async def get_dietary_protocols(user=Depends(get_current_user)) -> list[DietaryProtocolEntry]:
    row = _get_or_create_row(user["id"])
    return [DietaryProtocolEntry(**e) for e in (row.get("dietary_protocols") or [])]


@router.put("/api/health-profile/dietary-protocols", tags=["health-profile"])
async def put_dietary_protocols(
    body: DietaryProtocolsUpdateRequest,
    user=Depends(get_current_user),
) -> HealthProfileResponse:
    row = _get_or_create_row(user["id"])
    data = {
        "user_id": user["id"],
        "allergens": row.get("allergens") or [],
        "intolerances": row.get("intolerances") or [],
        "conditions": row.get("conditions") or [],
        "dietary_protocols": [e.model_dump() for e in body.dietary_protocols],
        "updated_at": _now_iso(),
    }
    result = supabase.table("health_profile").upsert(data, on_conflict="user_id").execute()
    return _row_to_response(result.data[0])
