from app.routers import trends


def test_research_for_returns_formatted_block(monkeypatch):
    monkeypatch.setattr(trends, "_user_condition_slugs", lambda uid: ["gerd"])
    monkeypatch.setattr(trends.knowledge, "search",
                        lambda q, conditions=None: [{"title": "T", "content": "body"}])
    out = trends._research_for("acid reflux", "u1")
    assert "T: body" in out


def test_research_for_swallows_errors(monkeypatch):
    def boom(*a, **k): raise RuntimeError("x")
    monkeypatch.setattr(trends, "_user_condition_slugs", lambda uid: [])
    monkeypatch.setattr(trends.knowledge, "search", boom)
    assert trends._research_for("q", "u1") == ""


def test_user_condition_slugs_lowercases_names(monkeypatch):
    class _R:
        data = {"conditions": [{"name": "GERD"}, {"name": "IBS"}]}

    class _Q:
        def select(self, *a): return self
        def eq(self, *a): return self
        def maybe_single(self): return self
        def execute(self): return _R()

    monkeypatch.setattr(trends.supabase, "table", lambda n: _Q())
    assert trends._user_condition_slugs("u1") == ["gerd", "ibs"]
