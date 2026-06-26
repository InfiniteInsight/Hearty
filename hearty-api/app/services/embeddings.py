"""Embedding service for the knowledge-base RAG (Spec 11 Layer 1).

Wraps litellm.embedding so the SAME model is used for both ingestion and query
(required for valid cosine similarity). Needs GEMINI_API_KEY at deploy time
(Google AI Studio key — litellm reads GEMINI_API_KEY for ``gemini/*`` models).
"""

import litellm

# Google AI Studio embedding model (litellm `gemini/` provider → uses GEMINI_API_KEY).
# Native output is 3072-dim; the migration's vector(3072) column matches.
EMBEDDING_MODEL = "gemini/gemini-embedding-001"


def embed(text: str) -> list[float]:
    """Return the embedding vector for a piece of text."""
    resp = litellm.embedding(model=EMBEDDING_MODEL, input=[text])
    return resp.data[0]["embedding"]
