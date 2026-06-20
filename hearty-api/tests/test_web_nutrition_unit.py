import json
from types import SimpleNamespace
from app.services import web_nutrition as wn


def _msg(content=None, tool_calls=None):
    return SimpleNamespace(choices=[SimpleNamespace(
        message=SimpleNamespace(content=content, tool_calls=tool_calls))])


def _tool_call(cid, query):
    return SimpleNamespace(id=cid, function=SimpleNamespace(
        name="web_search", arguments=json.dumps({"query": query})))


def test_brave_search_parses_results(monkeypatch):
    from unittest.mock import patch
    class _Resp:
        status_code = 200
        def json(self): return {"web": {"results": [
            {"title": "T", "url": "http://x", "description": "D"}]}}
        def raise_for_status(self): pass
    monkeypatch.setenv("BRAVE_SEARCH_API_KEY", "bk")
    with patch.object(wn.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp()
        out = wn.brave_search("clif bar nutrition")
    assert out[0]["url"] == "http://x"


def test_web_lookup_tool_loop_then_json():
    calls = {"searches": 0}
    def fake_search(q):
        calls["searches"] += 1
        return [{"title": "Clif", "url": "http://c", "description": "250 cal"}]
    seq = [
        _msg(tool_calls=[_tool_call("c1", "clif bar nutrition")]),  # round 1: search
        _msg(content=json.dumps({"item_name": "Clif Bar", "calories": 250,
             "total_fat_g": 6, "total_carbs_g": 44, "protein_g": 9,
             "source_url": "http://c"})),                            # round 2: answer
    ]
    def fake_complete(**kw): return seq.pop(0)
    out = wn.web_nutrition_lookup("clif bar", search=fake_search, complete=fake_complete)
    assert calls["searches"] == 1
    assert out["calories"] == 250 and out["source"] == "web_search" and out["tier"] == 3
    assert out["source_url"] == "http://c"


def test_web_lookup_no_data_returns_none():
    def fake_complete(**kw): return _msg(content="NO_DATA")
    out = wn.web_nutrition_lookup("zzz", search=lambda q: [], complete=fake_complete)
    assert out is None


def test_web_lookup_no_key_returns_none(monkeypatch):
    monkeypatch.delenv("BRAVE_SEARCH_API_KEY", raising=False)
    # default search path requires the key; with no key and the real default search,
    # the loop must bail to None without calling the model.
    out = wn.web_nutrition_lookup("clif bar")
    assert out is None


def test_malformed_tool_args_falls_back_to_description():
    seen = {}
    def fake_search(q):
        seen["q"] = q
        return [{"title": "x", "url": "http://x", "description": "d"}]
    bad = SimpleNamespace(id="c1", function=SimpleNamespace(name="web_search", arguments="{not json"))
    seq = [
        _msg(tool_calls=[bad]),
        _msg(content=json.dumps({"item_name": "Item", "calories": 100, "source_url": "http://x"})),
    ]
    out = wn.web_nutrition_lookup("clif bar", search=fake_search, complete=lambda **k: seq.pop(0))
    assert seen["q"] == "clif bar"   # fell back to description
    assert out["calories"] == 100


def test_multiple_tool_calls_in_one_round_all_execute():
    calls = []
    def fake_search(q):
        calls.append(q)
        return [{"title": "x", "url": "http://x", "description": "d"}]
    seq = [
        _msg(tool_calls=[_tool_call("c1", "q1"), _tool_call("c2", "q2")]),
        _msg(content=json.dumps({"item_name": "Item", "calories": 50, "source_url": "http://x"})),
    ]
    out = wn.web_nutrition_lookup("x", search=fake_search, complete=lambda **k: seq.pop(0))
    assert calls == ["q1", "q2"]
    assert out["calories"] == 50


def test_rounds_exhausted_returns_none():
    calls = {"n": 0}
    def fake_search(q):
        calls["n"] += 1
        return []
    def always_tool(**k):
        return _msg(tool_calls=[_tool_call("c", "q")])
    out = wn.web_nutrition_lookup("x", search=fake_search, complete=always_tool)
    assert out is None
    assert calls["n"] <= wn.WEB_MAX_TOOL_ROUNDS


def test_unparseable_final_json_returns_none():
    out = wn.web_nutrition_lookup("x", search=lambda q: [], complete=lambda **k: _msg(content="here you go: not json"))
    assert out is None
