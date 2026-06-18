"""Thin Supabase layer for food photos: Storage bucket + food_log_photos table.
Uses the service-key client (bypasses RLS) so every table read/write is manually
user-scoped. Storage paths are always {user_id}/{photo_id}.jpg."""

import os
from supabase import create_client

PHOTO_BUCKET = os.environ.get("PHOTO_BUCKET", "food-photos")
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def storage_path(user_id: str, photo_id: str) -> str:
    return f"{user_id}/{photo_id}.jpg"


def upload_bytes(path: str, data: bytes, content_type: str) -> None:
    supabase.storage.from_(PHOTO_BUCKET).upload(
        path, data, {"content-type": content_type, "upsert": "true"})


def download_bytes(path: str) -> bytes:
    return supabase.storage.from_(PHOTO_BUCKET).download(path)


def create_row(user_id: str, photo_id: str, photo_url: str, photo_type: str,
               meal_id: str | None) -> dict:
    row = {
        "id": photo_id, "user_id": user_id, "meal_id": meal_id,
        "photo_url": photo_url, "photo_type": photo_type,
        "processing_status": "processing",
    }
    return supabase.table("food_log_photos").insert(row).execute().data[0]


def get_photo(user_id: str, photo_id: str) -> dict | None:
    rows = (supabase.table("food_log_photos").select("*")
            .eq("user_id", user_id).eq("id", photo_id).execute()).data or []
    return rows[0] if rows else None


def set_processing(user_id: str, photo_id: str) -> None:
    supabase.table("food_log_photos").update({"processing_status": "processing",
        "extracted_data": None}).eq("user_id", user_id).eq("id", photo_id).execute()


def set_result(user_id: str, photo_id: str, extracted_data: dict) -> None:
    supabase.table("food_log_photos").update(
        {"processing_status": "complete", "extracted_data": extracted_data}) \
        .eq("user_id", user_id).eq("id", photo_id).execute()


def set_failed(user_id: str, photo_id: str, message: str) -> None:
    supabase.table("food_log_photos").update(
        {"processing_status": "failed", "extracted_data": {"error": message}}) \
        .eq("user_id", user_id).eq("id", photo_id).execute()
