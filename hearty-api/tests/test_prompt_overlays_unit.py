import types
import pytest
from app.services import prompt_overlays


class _Query:
    def __init__(self, store, table):
        self.store, self.table = store, table
        self._op = None; self._payload = None; self._filters = []; self._order = None
    def select(self, cols): self._op = "select"; return self
    def insert(self, payload): self._op = "insert"; self._payload = payload; return self
    def update(self, payload): self._op = "update"; self._payload = payload; return self
    def eq(self, c, v): self._filters.append((c, v)); return self
    def limit(self, *a, **k): return self
    def order(self, c, desc=False): self._order = (c, desc); return self
    def execute(self):
        self.store["calls"].append((self.table, self._op, self._payload, self._filters, self._order))
        if self._op == "select":
            key = f"{self.table}:rows"
            return types.SimpleNamespace(data=self.store.get(key, []))
        if self._op == "update":
            return types.SimpleNamespace(data=[{"surface": self._filters[0][1], **self._payload}])
        return types.SimpleNamespace(data=[dict(self._payload or {})])  # insert


class _FakeSupabase:
    def __init__(self, store): self.store = store
    def table(self, name): return _Query(self.store, name)


def _setup(monkeypatch, store):
    monkeypatch.setattr(prompt_overlays, "supabase", _FakeSupabase(store))


def test_get_overlay_returns_guidance(monkeypatch):
    _setup(monkeypatch, {"calls": [], "prompt_overlays:rows": [{"guidance": "be warm"}]})
    assert prompt_overlays.get_overlay("summary") == "be warm"


def test_get_overlay_missing_is_empty(monkeypatch):
    _setup(monkeypatch, {"calls": [], "prompt_overlays:rows": []})
    assert prompt_overlays.get_overlay("summary") == ""


def test_get_overlay_swallows_errors(monkeypatch):
    class _Boom:
        def table(self, n): raise RuntimeError("db down")
    monkeypatch.setattr(prompt_overlays, "supabase", _Boom())
    assert prompt_overlays.get_overlay("summary") == ""


def test_set_overlay_appends_version_and_updates(monkeypatch):
    store = {"calls": []}; _setup(monkeypatch, store)
    row = prompt_overlays.set_overlay("summary", "new guidance", "admin1")
    ops = [(t, op) for (t, op, _p, _f, _o) in store["calls"]]
    assert ("prompt_overlay_versions", "insert") in ops
    assert ("prompt_overlays", "update") in ops
    vins = next(p for (t, op, p, _f, _o) in store["calls"]
                if t == "prompt_overlay_versions" and op == "insert")
    assert vins["surface"] == "summary" and vins["guidance"] == "new guidance"
    assert vins["created_by"] == "admin1"
    assert row["guidance"] == "new guidance"


def test_set_overlay_rejects_unknown_surface(monkeypatch):
    _setup(monkeypatch, {"calls": []})
    with pytest.raises(ValueError):
        prompt_overlays.set_overlay("bogus", "x", "admin1")


def test_list_versions_ordered_desc(monkeypatch):
    store = {"calls": [], "prompt_overlay_versions:rows": [{"id": "v1", "guidance": "a"}]}
    _setup(monkeypatch, store)
    out = prompt_overlays.list_versions("summary")
    _t, _op, _p, filters, order = store["calls"][0]
    assert filters == [("surface", "summary")] and order == ("created_at", True)
    assert out[0]["id"] == "v1"


def test_revert_reapplies_version(monkeypatch):
    store = {"calls": [], "prompt_overlay_versions:rows": [{"guidance": "old text"}]}
    _setup(monkeypatch, store)
    prompt_overlays.revert("summary", "v9", "admin1")
    vins = [p for (t, op, p, _f, _o) in store["calls"]
            if t == "prompt_overlay_versions" and op == "insert"]
    assert vins and vins[-1]["guidance"] == "old text"
    # the version lookup is scoped to BOTH id and surface (no cross-surface revert)
    sel = next(f for (t, op, _p, f, _o) in store["calls"]
               if t == "prompt_overlay_versions" and op == "select")
    assert ("id", "v9") in sel and ("surface", "summary") in sel
