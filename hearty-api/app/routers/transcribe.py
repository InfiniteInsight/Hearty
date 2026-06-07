import logging
import os

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.auth import get_current_user

logger = logging.getLogger(__name__)

router = APIRouter()

# Google Cloud Speech-to-Text v1 synchronous recognize. The API key is
# server-side only; the Flutter client authenticates to *us* with its JWT.
# NOTE (deployment): disable data-logging at the GCP project level so audio is
# transient-in-transit only — there is no per-request flag for it.
_GOOGLE_STT_URL = "https://speech.googleapis.com/v1/speech:recognize"
_API_KEY = os.getenv("GOOGLE_STT_API_KEY", "")
_LANGUAGE = os.getenv("GOOGLE_STT_LANGUAGE", "en-US")
_MODEL = os.getenv("GOOGLE_STT_MODEL", "latest_long")


class TranscribeRequest(BaseModel):
    # base64-encoded headerless LINEAR16 PCM (mono).
    audio: str
    sample_rate: int = 16000


class TranscribeResponse(BaseModel):
    transcript: str


@router.post("/api/transcribe", status_code=200)
async def transcribe(
    body: TranscribeRequest,
    user=Depends(get_current_user),
) -> TranscribeResponse:
    if not _API_KEY:
        logger.error("GOOGLE_STT_API_KEY not configured")
        raise HTTPException(status_code=503, detail="Transcription unavailable")
    if not body.audio:
        return TranscribeResponse(transcript="")

    payload = {
        "config": {
            "encoding": "LINEAR16",
            "sampleRateHertz": body.sample_rate,
            "languageCode": _LANGUAGE,
            "model": _MODEL,
            "enableAutomaticPunctuation": True,
        },
        "audio": {"content": body.audio},
    }
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                _GOOGLE_STT_URL, params={"key": _API_KEY}, json=payload
            )
            resp.raise_for_status()
            data = resp.json()
    except httpx.HTTPError as e:
        logger.error("Google STT request failed: %s", e)
        raise HTTPException(status_code=502, detail="Transcription failed")

    # results[].alternatives[0].transcript — concatenate result segments.
    transcript = " ".join(
        r["alternatives"][0]["transcript"].strip()
        for r in data.get("results", [])
        if r.get("alternatives")
    ).strip()
    return TranscribeResponse(transcript=transcript)
