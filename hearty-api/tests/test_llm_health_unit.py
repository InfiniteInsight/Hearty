import types
from app.services import llm_health as lh


class _Tbl:
    def __init__(self, log): self.log = log; self._payload = None
    def update(self, payload): self._payload = payload; return self
    def eq(self, *a, **k): return self
    def execute(self): self.log.append(self._payload); return types.SimpleNamespace(data=[{"id": 1}])


def _fake(log):
    return types.SimpleNamespace(table=lambda n: _Tbl(log))


def test_record_ok_sets_ok_and_model(monkeypatch):
    log = []
    monkeypatch.setattr(lh, "supabase", _fake(log))
    lh.record_llm_ok("claude-sonnet-4-6")
    assert log[0]["llm_last_ok_at"] is not None
    assert log[0]["llm_last_model"] == "claude-sonnet-4-6"
    assert "llm_last_error_at" not in log[0]


def test_record_error_sets_error_truncated(monkeypatch):
    log = []
    monkeypatch.setattr(lh, "supabase", _fake(log))
    lh.record_llm_error("m", "x" * 999)
    assert log[0]["llm_last_error_at"] is not None
    assert len(log[0]["llm_last_error"]) == 500
    assert log[0]["llm_last_model"] == "m"


def test_logger_success_calls_record_ok(monkeypatch):
    seen = {}
    monkeypatch.setattr(lh, "record_llm_ok", lambda model: seen.update({"ok": model}))
    lh.HealthLogger().log_success_event({"model": "mm"}, None, None, None)
    assert seen["ok"] == "mm"


def test_logger_failure_calls_record_error(monkeypatch):
    seen = {}
    monkeypatch.setattr(lh, "record_llm_error", lambda model, error: seen.update({"err": (model, error)}))
    lh.HealthLogger().log_failure_event({"model": "mm", "exception": RuntimeError("boom")}, None, None, None)
    assert seen["err"][0] == "mm" and "boom" in seen["err"][1]


def test_logger_swallows_recorder_exception(monkeypatch):
    def _boom(model): raise RuntimeError("db down")
    monkeypatch.setattr(lh, "record_llm_ok", _boom)
    # must not raise
    lh.HealthLogger().log_success_event({"model": "mm"}, None, None, None)
