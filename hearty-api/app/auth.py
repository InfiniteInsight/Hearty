from fastapi import HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from supabase import create_client
import os

security = HTTPBearer()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Security(security)
) -> dict:
    token = credentials.credentials
    try:
        response = supabase.auth.get_user(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    if response.user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return {"id": response.user.id, "email": response.user.email}


async def get_current_admin(
    credentials: HTTPAuthorizationCredentials = Security(security)
) -> dict:
    """Owner-only. Validates the token and requires app_metadata.role == 'admin'.
    app_metadata is server-set (not user-editable) — safe for authorization."""
    token = credentials.credentials
    try:
        response = supabase.auth.get_user(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    user = response.user
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    role = (getattr(user, "app_metadata", None) or {}).get("role")
    if role != "admin":
        raise HTTPException(status_code=403, detail="admin only")
    return {"id": user.id, "email": user.email}
