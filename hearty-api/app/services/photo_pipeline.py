"""Background worker: turn an uploaded photo into structured extracted_data.
Dispatches by photo_type; only food_plate is supported in the MVP. All failures
are non-blocking and recorded as processing_status='failed' (the meal log is
never affected). The content-type for the data URL is sniffed from the actual
image bytes so a PNG upload isn't mislabeled as JPEG to the vision model."""

import logging

from app.services import photo_store, food_plate

logger = logging.getLogger(__name__)


def _sniff_content_type(image: bytes) -> str:
    """PNG files start with the 8-byte signature \\x89PNG\\r\\n\\x1a\\n; everything
    else we accept is JPEG. Used to label the data URL sent to the vision model."""
    if image.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    return "image/jpeg"


def process_photo(photo_id: str, user_id: str) -> None:
    row = photo_store.get_photo(user_id, photo_id)
    if not row:
        return
    # Cache: never re-process an already-complete photo (Claude calls cost money).
    if row.get("processing_status") == "complete" and row.get("extracted_data"):
        return
    try:
        image = photo_store.download_bytes(row["photo_url"])
        content_type = _sniff_content_type(image)
        photo_type = row.get("photo_type") or "food_plate"
        if photo_type == "food_plate":
            result = food_plate.analyze_food_plate(image, content_type)
        else:
            photo_store.set_failed(
                user_id, photo_id, f"Photo type '{photo_type}' not yet supported")
            return
        photo_store.set_result(user_id, photo_id, result)
    except Exception as e:  # non-blocking: record and move on
        logger.warning("process_photo failed for %s: %s", photo_id, e)
        photo_store.set_failed(
            user_id, photo_id, "Vision processing failed — please try again")
