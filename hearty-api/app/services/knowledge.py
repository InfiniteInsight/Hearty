"""Knowledge-base store + retrieval for the RAG corpus (Spec 11 Layer 1).

Owns the service-key Supabase client for the knowledge_base table. Retrieval is
best-effort: any embedding/RPC failure or empty corpus yields [] so a RAG miss
never breaks the AI call that depends on it.
"""

import logging
import os

from supabase import create_client

from app.services.embeddings import embed

logger = logging.getLogger(__name__)
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

# Columns returned to the admin list view — never the embedding (heavy, useless to UI).
_LIST_COLUMNS = "id, source, title, conditions, tags, active, created_at"


def add_entry(title, content, conditions=None, source="manual", source_id=None) -> dict:
    """Embed ``content`` and insert a corpus row. Returns the row WITHOUT the
    embedding. Embedding failures propagate (admin write path — the owner should
    see that an entry wasn't embedded)."""
    vector = embed(content)
    row = {
        "title": title,
        "content": content,
        "content_embedding": vector,
        "conditions": conditions or [],
        "source": source,
        "source_id": source_id,
    }
    inserted = supabase.table("knowledge_base").insert(row).execute().data[0]
    inserted.pop("content_embedding", None)
    return inserted


def search(query_text, k=4, conditions=None) -> list[dict]:
    """Return up to ``k`` corpus rows most similar to ``query_text``. Best-effort:
    any embedding/RPC error or empty corpus yields []."""
    try:
        vector = embed(query_text)
        resp = supabase.rpc("match_knowledge", {
            "query_embedding": vector,
            "match_count": k,
            "filter_conditions": conditions or None,
        }).execute()
        return resp.data or []
    except Exception as e:  # never let a RAG miss break the caller's AI call
        logger.error("knowledge.search failed: %s", e, exc_info=True)
        return []


def format_context(rows) -> str:
    """Render retrieved rows as a system-prompt block. '' when no rows."""
    if not rows:
        return ""
    lines = ["Relevant current research (ground your explanation in this; "
             "still observations, not diagnoses):"]
    for r in rows:
        title = r.get("title") or "research"
        lines.append(f"- {title}: {r['content']}")
    return "\n".join(lines)


def list_entries() -> list[dict]:
    return (supabase.table("knowledge_base")
            .select(_LIST_COLUMNS)
            .order("created_at", desc=True)
            .execute()).data or []


def delete_entry(entry_id) -> None:
    supabase.table("knowledge_base").delete().eq("id", entry_id).execute()


def set_active(entry_id, active) -> dict:
    res = (supabase.table("knowledge_base")
           .update({"active": active})
           .eq("id", entry_id)
           .execute())
    return res.data[0] if res.data else {}
