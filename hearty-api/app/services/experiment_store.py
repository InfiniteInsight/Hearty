"""Thin Supabase store for experiments. Window math lives here; adherence and
evaluation are computed elsewhere."""

import os
from datetime import datetime, timezone, timedelta

from supabase import create_client

EXPERIMENT_DAYS = int(os.environ.get("EXPERIMENT_DAYS", "14"))
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def create_experiment(user_id: str, category: str, outcome_type: str,
                      outcome_name: str) -> dict:
    now = datetime.now(timezone.utc)
    end = now + timedelta(days=EXPERIMENT_DAYS)
    baseline_start = now - timedelta(days=EXPERIMENT_DAYS)
    row = {
        "user_id": user_id, "category": category, "direction": "eliminate",
        "outcome_type": outcome_type, "outcome_name": outcome_name,
        "baseline_start": baseline_start.isoformat(),
        "baseline_end": now.isoformat(),
        "experiment_start": now.isoformat(),
        "experiment_end": end.isoformat(),
        "status": "active",
    }
    return supabase.table("experiments").insert(row).execute().data[0]


def get_active(user_id: str) -> list[dict]:
    return (supabase.table("experiments").select("*")
            .eq("user_id", user_id).eq("status", "active").execute()).data or []


def get_one(user_id: str, experiment_id: str) -> dict | None:
    rows = (supabase.table("experiments").select("*")
            .eq("user_id", user_id).eq("id", experiment_id).execute()).data or []
    return rows[0] if rows else None


def abandon_experiment(user_id: str, experiment_id: str) -> None:
    supabase.table("experiments").update({"status": "abandoned"}) \
        .eq("user_id", user_id).eq("id", experiment_id).execute()


def restart_experiment(user_id: str, experiment_id: str) -> dict:
    now = datetime.now(timezone.utc)
    vals = {
        "experiment_start": now.isoformat(),
        "experiment_end": (now + timedelta(days=EXPERIMENT_DAYS)).isoformat(),
        "baseline_start": (now - timedelta(days=EXPERIMENT_DAYS)).isoformat(),
        "baseline_end": now.isoformat(),
        "nudged_at": None,
    }
    return (supabase.table("experiments").update(vals)
            .eq("user_id", user_id).eq("id", experiment_id).execute()).data[0]


def mark_completed(user_id: str, experiment_id: str, result: dict) -> None:
    supabase.table("experiments").update({"status": "completed", "result": result}) \
        .eq("user_id", user_id).eq("id", experiment_id).execute()


def mark_nudged(user_id: str, experiment_id: str) -> None:
    supabase.table("experiments").update(
        {"nudged_at": datetime.now(timezone.utc).isoformat()}) \
        .eq("user_id", user_id).eq("id", experiment_id).execute()
