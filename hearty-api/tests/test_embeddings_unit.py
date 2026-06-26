import types
from app.services import embeddings


def test_embed_returns_vector_and_uses_gemini_model(monkeypatch):
    captured = {}

    def fake_embedding(model, input):
        captured["model"] = model
        captured["input"] = input
        # Mirrors litellm's EmbeddingResponse: .data is a list of dict-like
        # objects each carrying an "embedding" key.
        return types.SimpleNamespace(data=[{"embedding": [0.1, 0.2, 0.3]}])

    monkeypatch.setattr(embeddings.litellm, "embedding", fake_embedding)
    out = embeddings.embed("hello world")
    assert out == [0.1, 0.2, 0.3]
    assert captured["model"] == "gemini/gemini-embedding-001"
    assert captured["input"] == ["hello world"]
