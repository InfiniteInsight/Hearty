from app.services import photo_store as ps


class _Result:
    def __init__(self, data): self.data = data


def test_create_row_inserts_processing(monkeypatch):
    rec = {}
    class _T:
        def insert(self, row): rec["row"] = row; return self
        def execute(self): return _Result([{**rec["row"], "id": "p1"}])
    monkeypatch.setattr(ps, "supabase", type("S", (), {"table": lambda s, n: _T()})())

    out = ps.create_row("u1", "p1", "u1/p1.jpg", "food_plate", meal_id=None)
    row = rec["row"]
    assert row["id"] == "p1" and row["user_id"] == "u1"
    assert row["photo_url"] == "u1/p1.jpg" and row["photo_type"] == "food_plate"
    assert row["processing_status"] == "processing"
    assert out["id"] == "p1"


def test_upload_bytes_targets_bucket_and_path(monkeypatch):
    rec = {}
    class _Bucket:
        def upload(self, path, file, file_options=None):
            rec["path"] = path; rec["file"] = file; rec["opts"] = file_options; return {}
    class _Storage:
        def from_(self, name): rec["bucket"] = name; return _Bucket()
    monkeypatch.setattr(ps, "supabase", type("S", (), {"storage": _Storage()})())

    ps.upload_bytes("u1/p1.jpg", b"\xff\xd8\xff", "image/jpeg")
    assert rec["bucket"] == "food-photos"
    assert rec["path"] == "u1/p1.jpg"
    assert rec["file"] == b"\xff\xd8\xff"
    assert rec["opts"]["content-type"] == "image/jpeg"


def test_set_result_writes_complete(monkeypatch):
    rec = {}
    class _T:
        def update(self, vals): rec["vals"] = vals; return self
        def eq(self, *a, **k): return self
        def execute(self): return _Result([{"id": "p1"}])
    monkeypatch.setattr(ps, "supabase", type("S", (), {"table": lambda s, n: _T()})())
    ps.set_result("u1", "p1", {"foods": []})
    assert rec["vals"]["processing_status"] == "complete"
    assert rec["vals"]["extracted_data"] == {"foods": []}


def test_get_photo_user_scoped(monkeypatch):
    rec = {}
    class _T:
        def select(self, *a, **k): return self
        def eq(self, col, val): rec.setdefault("eqs", []).append((col, val)); return self
        def execute(self): return _Result([{"id": "p1", "user_id": "u1"}])
    monkeypatch.setattr(ps, "supabase", type("S", (), {"table": lambda s, n: _T()})())
    out = ps.get_photo("u1", "p1")
    assert out["id"] == "p1"
    assert ("user_id", "u1") in rec["eqs"] and ("id", "p1") in rec["eqs"]
