# app/routers/photos.py
# Photo processing is implemented in Spec 06 (AI Vision — Phase 4 roadmap).
# These stubs register the routes in the OpenAPI schema and return 501 until Spec 06 is complete.
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from uuid import UUID
from app.auth import get_current_user
from app.models.schemas import PhotoUploadResponse, PhotoStatusResponse

router = APIRouter()

@router.post("/api/photos", status_code=202)
async def upload_photo(
    file: UploadFile = File(...),
    type: str = Form(...),
    user=Depends(get_current_user)
) -> PhotoUploadResponse:
    raise HTTPException(status_code=501, detail="Photo upload not yet implemented. See Spec 06.")

@router.get("/api/photos/{photo_id}/status")
async def get_photo_status(
    photo_id: UUID,
    user=Depends(get_current_user)
) -> PhotoStatusResponse:
    raise HTTPException(status_code=501, detail="Photo status not yet implemented. See Spec 06.")
