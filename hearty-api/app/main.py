import logging
import os
from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.health_profile.defaults_router import router as defaults_router
from app.health_profile.router import router as health_profile_router
from app.licensing import require_active_license
from app.routers import auth_hooks, chat, meals, symptoms, trends, export, photos, preferences, transcribe, checkin, experiments, food, account, license, admin, internal

logger = logging.getLogger(__name__)

# Fail-closed CORS: an unset/blank ALLOWED_ORIGINS denies all cross-origin
# requests rather than silently opening to "*" on misconfiguration.
def _parse_origins(env: str) -> list[str]:
    return [o.strip() for o in env.split(",") if o.strip()]


_allowed_origins = _parse_origins(os.getenv("ALLOWED_ORIGINS", ""))
if not _allowed_origins:
    logger.warning("ALLOWED_ORIGINS is not set — all cross-origin requests will be denied")

@asynccontextmanager
async def lifespan(app: FastAPI):
    from app.services import llm_health
    llm_health.register()
    yield

app = FastAPI(
    title="Hearty API",
    version="1.0.0",
    description="Personal food and symptom journal REST API",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(defaults_router, prefix="/api/health-profile")
app.include_router(health_profile_router, dependencies=[Depends(require_active_license)])
app.include_router(auth_hooks.router)
app.include_router(chat.router, dependencies=[Depends(require_active_license)])
app.include_router(meals.router, dependencies=[Depends(require_active_license)])
app.include_router(symptoms.router, dependencies=[Depends(require_active_license)])
app.include_router(trends.router, dependencies=[Depends(require_active_license)])
app.include_router(export.router, dependencies=[Depends(require_active_license)])
app.include_router(photos.router, dependencies=[Depends(require_active_license)])
app.include_router(preferences.router, dependencies=[Depends(require_active_license)])
app.include_router(transcribe.router, dependencies=[Depends(require_active_license)])
app.include_router(checkin.router, dependencies=[Depends(require_active_license)])
app.include_router(experiments.router, dependencies=[Depends(require_active_license)])
app.include_router(food.router, dependencies=[Depends(require_active_license)])
app.include_router(account.router)
app.include_router(license.router)
app.include_router(admin.router)
app.include_router(internal.router)

@app.get("/health")
async def health_check():
    return {"status": "ok"}
