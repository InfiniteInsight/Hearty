import logging
import os
from datetime import datetime, timezone

import litellm
from litellm.integrations.custom_logger import CustomLogger
from supabase import create_client

logger = logging.getLogger(__name__)
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def record_llm_ok(model: str | None) -> None:
    """Stamp the last successful LLM call. Best-effort; the row is seeded (id=1)."""
    supabase.table("service_health").update({
        "llm_last_ok_at": _now_iso(), "llm_last_model": model, "updated_at": _now_iso(),
    }).eq("id", 1).execute()


def record_llm_error(model: str | None, error: str) -> None:
    """Stamp the last failed LLM call (error truncated)."""
    supabase.table("service_health").update({
        "llm_last_error_at": _now_iso(), "llm_last_error": (error or "")[:500],
        "llm_last_model": model, "updated_at": _now_iso(),
    }).eq("id", 1).execute()


class HealthLogger(CustomLogger):
    """Global litellm callback — records every completion's outcome to service_health.
    Wrapped so a recorder failure can never affect the AI call or litellm.

    Covers the app's synchronous `litellm.completion` calls (the only mode used).
    If an async `litellm.acompletion` call site is ever added, also override
    `async_log_success_event` / `async_log_failure_event` or its outcome won't be
    recorded."""
    def log_success_event(self, kwargs, response_obj, start_time, end_time):
        try:
            record_llm_ok(kwargs.get("model"))
        except Exception as e:
            logger.warning("llm health record (ok) failed: %s", e)

    def log_failure_event(self, kwargs, response_obj, start_time, end_time):
        try:
            record_llm_error(kwargs.get("model"), str(kwargs.get("exception") or response_obj))
        except Exception as e:
            logger.warning("llm health record (error) failed: %s", e)


def register() -> None:
    """Install the callback for all litellm completions (idempotent)."""
    if not any(isinstance(cb, HealthLogger) for cb in (litellm.callbacks or [])):
        litellm.callbacks = [HealthLogger()]
