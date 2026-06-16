# app/routers/photos.py
# AI Vision food-plate MVP (Spec 06). Async: upload → store → BackgroundTasks
# worker → poll status. Only food_plate is processed; other types fail cleanly.
import os
from uuid import uuid4

from fastapi import (APIRouter, Depends, HTTPException, UploadFile, File, Form,
                     BackgroundTasks)

from app.auth import get_current_user
from app.models.schemas import PhotoUploadResponse, PhotoStatusResponse
from app.services import photo_store, photo_pipeline

router = APIRouter()

MAX_PHOTO_BYTES = int(os.environ.get("MAX_PHOTO_BYTES", str(10 * 1024 * 1024)))
_ALLOWED_TYPES = {"image/jpeg", "image/png"}
_VALID_PHOTO_TYPES = {"food_plate", "barcode", "nutrition_label", "food_label"}


@router.post("/api/photos", status_code=202)
async def upload_photo(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    type: str = Form("food_plate"),
    meal_id: str | None = Form(None),
    user=Depends(get_current_user),
) -> PhotoUploadResponse:
    if file.content_type not in _ALLOWED_TYPES:
        raise HTTPException(status_code=400,
            detail="Unsupported file type — please use JPEG or PNG")
    if type not in _VALID_PHOTO_TYPES:
        raise HTTPException(status_code=400, detail="Invalid photo type")
    data = await file.read()
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Image too large (max 10 MB)")
    if not data:
        raise HTTPException(status_code=400, detail="Empty file")

    user_id = user["id"]
    photo_id = str(uuid4())
    path = photo_store.storage_path(user_id, photo_id)
    photo_store.upload_bytes(path, data, file.content_type)
    photo_store.create_row(user_id, photo_id, path, type, meal_id)
    background_tasks.add_task(photo_pipeline.process_photo, photo_id, user_id)

    return PhotoUploadResponse(id=photo_id, type=type, status="processing",
                               meal_id=meal_id, message="Processing your photo…")


@router.get("/api/photos/{photo_id}/status")
async def get_photo_status(photo_id: str,
                           user=Depends(get_current_user)) -> PhotoStatusResponse:
    row = photo_store.get_photo(user["id"], photo_id)
    if not row:
        raise HTTPException(status_code=404, detail="Photo not found")
    data = row.get("extracted_data") or {}
    status = row["processing_status"]
    error = data.get("error") if status == "failed" else None
    result = data if status == "complete" else None
    return PhotoStatusResponse(id=row["id"], type=row.get("photo_type") or "food_plate",
                               status=status, result=result, error=error)


@router.post("/api/photos/{photo_id}/retry", status_code=202)
async def retry_photo(photo_id: str, background_tasks: BackgroundTasks,
                      user=Depends(get_current_user)) -> PhotoStatusResponse:
    user_id = user["id"]
    row = photo_store.get_photo(user_id, photo_id)
    if not row:
        raise HTTPException(status_code=404, detail="Photo not found")
    photo_store.set_processing(user_id, photo_id)
    background_tasks.add_task(photo_pipeline.process_photo, photo_id, user_id)
    return PhotoStatusResponse(id=photo_id, type=row.get("photo_type") or "food_plate",
                               status="processing", result=None, error=None)
