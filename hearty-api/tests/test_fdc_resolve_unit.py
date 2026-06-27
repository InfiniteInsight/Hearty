import types
from app.services import fdc_resolve as fr


def _llm(content):
    return types.SimpleNamespace(choices=[types.SimpleNamespace(
        message=types.SimpleNamespace(content=content))])


def test_resolve_picks_and_fetches_detail(monkeypatch):
    monkeypatch.setattr(fr, "fdc_search", lambda q: [
        {"fdc_id": 111, "description": "Apples, fuji, raw", "data_type": "Foundation"},
        {"fdc_id": 222, "description": "Croissants, apple", "data_type": "SR Legacy"}])
    seen = {}
    monkeypatch.setattr(fr, "fdc_detail",
                        lambda fid: seen.update(fid=fid) or {"item_name": "Apples, fuji, raw", "calories": 63, "source": "usda_fdc", "tier": 2})
    monkeypatch.setattr(fr.litellm, "completion", lambda **k: _llm('{"index": 0}'))
    out = fr.resolve("apple")
    assert out["source"] == "usda_fdc" and seen["fid"] == 111


def test_resolve_none_when_llm_says_null(monkeypatch):
    monkeypatch.setattr(fr, "fdc_search", lambda q: [{"fdc_id": 1, "description": "x", "data_type": "Foundation"}])
    called = {"detail": False}
    monkeypatch.setattr(fr, "fdc_detail", lambda fid: called.__setitem__("detail", True) or {"x": 1})
    monkeypatch.setattr(fr.litellm, "completion", lambda **k: _llm('{"index": null}'))
    assert fr.resolve("zzz") is None and called["detail"] is False


def test_resolve_no_candidates_skips_llm(monkeypatch):
    called = {"llm": False}
    monkeypatch.setattr(fr, "fdc_search", lambda q: [])
    monkeypatch.setattr(fr.litellm, "completion", lambda **k: called.__setitem__("llm", True) or _llm('{"index": 0}'))
    assert fr.resolve("apple") is None and called["llm"] is False


def test_resolve_handles_malformed_llm_json(monkeypatch):
    monkeypatch.setattr(fr, "fdc_search", lambda q: [{"fdc_id": 1, "description": "x", "data_type": "Foundation"}])
    called = {"detail": False}
    monkeypatch.setattr(fr, "fdc_detail", lambda fid: called.__setitem__("detail", True) or {"x": 1})
    monkeypatch.setattr(fr.litellm, "completion", lambda **k: _llm('{"index": }'))  # braced but invalid
    assert fr.resolve("apple") is None and called["detail"] is False


def test_resolve_swallows_errors(monkeypatch):
    monkeypatch.setattr(fr, "fdc_search", lambda q: [{"fdc_id": 1, "description": "x", "data_type": "Foundation"}])
    monkeypatch.setattr(fr.litellm, "completion", lambda **k: (_ for _ in ()).throw(RuntimeError("llm down")))
    assert fr.resolve("apple") is None
