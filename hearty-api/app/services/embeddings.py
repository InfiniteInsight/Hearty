"""Embedding service for the knowledge-base RAG (Spec 11 Layer 1).

Wraps litellm.embedding so the SAME model is used for both ingestion and query
(required for valid cosine similarity). Needs OPENAI_API_KEY at deploy time.
"""

import litellm

EMBEDDING_MODEL = "text-embedding-3-small"  # 1536 dims; matches vector(1536)


def embed(text: str) -> list[float]:
    """Return the embedding vector for a piece of text."""
    resp = litellm.embedding(model=EMBEDDING_MODEL, input=[text])
    return resp.data[0]["embedding"]
