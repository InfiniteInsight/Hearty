"""Shared server-side nutrition cache. Global (not user-scoped); only the
service-key client touches food_cache. Expiry is evaluated at read time."""

import os
from datetime import datetime, timezone, timedelta

from supabase import create_client

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def get_cached(lookup_key: str) -> dict | None:
    rows = (supabase.table("food_cache").select("*")
            .eq("lookup_key", lookup_key).limit(1).execute()).data or []
    if not rows:
        return None
    row = rows[0]
    cached_at = datetime.fromisoformat(row["cached_at"])
    if cached_at.tzinfo is None:
        cached_at = cached_at.replace(tzinfo=timezone.utc)
    if cached_at + timedelta(days=row["ttl_days"]) <= datetime.now(timezone.utc):
        return None  # expired → treat as miss
    return row["nutrition_data"]


def set_cached(lookup_key: str, source: str, nutrition_data: dict,
               ttl_days: int) -> None:
    supabase.table("food_cache").upsert({
        "lookup_key": lookup_key, "source": source,
        "nutrition_data": nutrition_data, "ttl_days": ttl_days,
        "cached_at": datetime.now(timezone.utc).isoformat(),
    }, on_conflict="lookup_key").execute()
