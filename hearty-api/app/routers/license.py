from fastapi import APIRouter, Depends

from app.auth import get_current_user
from app.licensing import _license_state

router = APIRouter()


@router.get("/api/license/status")
async def license_status(user=Depends(get_current_user)) -> dict:
    state, expires_at = _license_state(user["id"])
    return {"status": state, "expires_at": expires_at}
