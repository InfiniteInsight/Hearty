from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.health_profile.defaults_router import router as defaults_router
# from app.routers import meals, symptoms, wellbeing, trends, export, health_profile, photos
# from app.routers import auth_hooks

@asynccontextmanager
async def lifespan(app: FastAPI):
    yield

app = FastAPI(
    title="Hearty API",
    version="1.0.0",
    description="Personal food and symptom journal REST API",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(defaults_router, prefix="/api/health-profile")

@app.get("/health")
async def health_check():
    return {"status": "ok"}
