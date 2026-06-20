from datetime import datetime, timezone, timedelta
from app.services import food_cache as fc


class _Result:
    def __init__(self, data): self.data = data


def _supa(rows, rec=None):
    class _T:
        def select(self, *a, **k): return self
        def eq(self, *a, **k): return self
        def limit(self, *a, **k): return self
        def upsert(self, row, **k):
            if rec is not None: rec["upsert"] = row
            return self
        def execute(self): return _Result(rows)
    return type("S", (), {"table": lambda s, n: _T()})()


def test_get_cached_returns_fresh(monkeypatch):
    cached_at = (datetime.now(timezone.utc) - timedelta(days=5)).isoformat()
    monkeypatch.setattr(fc, "supabase", _supa([{
        "lookup_key": "barcode:1", "source": "open_food_facts",
        "nutrition_data": {"calories": 100}, "cached_at": cached_at, "ttl_days": 30}]))
    out = fc.get_cached("barcode:1")
    assert out["calories"] == 100


def test_get_cached_expired_returns_none(monkeypatch):
    cached_at = (datetime.now(timezone.utc) - timedelta(days=40)).isoformat()
    monkeypatch.setattr(fc, "supabase", _supa([{
        "lookup_key": "barcode:1", "source": "x",
        "nutrition_data": {"calories": 100}, "cached_at": cached_at, "ttl_days": 30}]))
    assert fc.get_cached("barcode:1") is None


def test_get_cached_miss_returns_none(monkeypatch):
    monkeypatch.setattr(fc, "supabase", _supa([]))
    assert fc.get_cached("barcode:nope") is None


def test_set_cached_upserts_by_key(monkeypatch):
    rec = {}
    monkeypatch.setattr(fc, "supabase", _supa([], rec))
    fc.set_cached("barcode:1", "open_food_facts", {"calories": 100}, 30)
    assert rec["upsert"]["lookup_key"] == "barcode:1"
    assert rec["upsert"]["ttl_days"] == 30
    assert rec["upsert"]["nutrition_data"] == {"calories": 100}
