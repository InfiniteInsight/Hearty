import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user
from app.models.schemas import (
    CreateExperimentRequest, ExperimentResponse, ActiveExperimentsResponse,
)
from app.services import experiment_store, experiment_adherence, experiment_evaluator
from app.services import signal_engine

router = APIRouter()

logger = logging.getLogger(__name__)


def _to_response(row: dict, **extra) -> ExperimentResponse:
    return ExperimentResponse(
        id=row["id"], category=row["category"], direction=row["direction"],
        outcome_type=row["outcome_type"], outcome_name=row["outcome_name"],
        experiment_start=row["experiment_start"], experiment_end=row["experiment_end"],
        status=row["status"], result=row.get("result"), nudged_at=row.get("nudged_at"),
        **extra,
    )


@router.post("/api/experiments", status_code=200)
async def create_experiment(body: CreateExperimentRequest,
                            user=Depends(get_current_user)) -> ExperimentResponse:
    try:
        row = experiment_store.create_experiment(
            user["id"], body.category, body.outcome_type, body.outcome_name)
    except Exception as e:
        # partial-unique violation = an active experiment already exists for this pattern
        logger.warning("create_experiment failed, returning 409: %s", e)
        raise HTTPException(status_code=409, detail="active experiment already exists")
    return _to_response(row)


@router.get("/api/experiments/active", status_code=200)
async def active_experiments(user=Depends(get_current_user)) -> ActiveExperimentsResponse:
    user_id = user["id"]
    out = []
    for row in experiment_store.get_active(user_id):
        meals, _sym, _wb = signal_engine._load_between(
            user_id, row["experiment_start"], datetime.now(timezone.utc).isoformat())
        adh = experiment_adherence.compute_adherence(meals, row["category"])
        nudge = experiment_adherence.should_nudge(
            adh["adherence"], adh["logged_days"], row.get("nudged_at"))
        out.append(_to_response(row, adherence=adh["adherence"],
                                logged_days=adh["logged_days"], nudge_suggested=nudge))
    return ActiveExperimentsResponse(experiments=out)


@router.post("/api/experiments/{experiment_id}/evaluate", status_code=200)
async def evaluate_experiment(experiment_id: str,
                              user=Depends(get_current_user)) -> ExperimentResponse:
    user_id = user["id"]
    row = experiment_store.get_one(user_id, experiment_id)
    if not row:
        raise HTTPException(status_code=404, detail="experiment not found")
    b_meals, b_sym, b_wb = signal_engine._load_between(
        user_id, row["baseline_start"], row["baseline_end"])
    e_meals, e_sym, e_wb = signal_engine._load_between(
        user_id, row["experiment_start"], row["experiment_end"])
    adh = experiment_adherence.compute_adherence(e_meals, row["category"])
    b_adh = experiment_adherence.compute_adherence(b_meals, row["category"])
    result = experiment_evaluator.evaluate(
        outcome_type=row["outcome_type"], outcome_name=row["outcome_name"],
        baseline_symptoms=b_sym, experiment_symptoms=e_sym,
        baseline_wellbeing=b_wb, experiment_wellbeing=e_wb,
        baseline_logged_days=b_adh["logged_days"],
        experiment_logged_days=adh["logged_days"], adherence=adh)
    experiment_store.mark_completed(user_id, experiment_id, result)
    row = {**row, "status": "completed", "result": result}
    return _to_response(row)


@router.post("/api/experiments/{experiment_id}/abandon", status_code=200)
async def abandon(experiment_id: str, user=Depends(get_current_user)) -> dict:
    if not experiment_store.get_one(user["id"], experiment_id):
        raise HTTPException(status_code=404, detail="experiment not found")
    experiment_store.abandon_experiment(user["id"], experiment_id)
    return {"ok": True}


@router.post("/api/experiments/{experiment_id}/restart", status_code=200)
async def restart(experiment_id: str, user=Depends(get_current_user)) -> ExperimentResponse:
    if not experiment_store.get_one(user["id"], experiment_id):
        raise HTTPException(status_code=404, detail="experiment not found")
    row = experiment_store.restart_experiment(user["id"], experiment_id)
    return _to_response(row)


@router.post("/api/experiments/{experiment_id}/ack-nudge", status_code=200)
async def ack_nudge(experiment_id: str, user=Depends(get_current_user)) -> dict:
    if not experiment_store.get_one(user["id"], experiment_id):
        raise HTTPException(status_code=404, detail="experiment not found")
    experiment_store.mark_nudged(user["id"], experiment_id)
    return {"ok": True}
