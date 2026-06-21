from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import account as acct


class _Q:
    """Records delete calls; returns empty data for selects."""
    def __init__(self, log, table):
        self.log = log
        self.table = table
        self._op = None
        self._eq = (None, None)

    def select(self, *a, **k):
        self._op = "select"
        return self

    def delete(self):
        self._op = "delete"
        return self

    def eq(self, col, val):
        self._eq = (col, val)
        return self

    def execute(self):
        if self._op == "delete":
            self.log.append(("delete", self.table, self._eq[1]))
        return type("R", (), {"data": []})()


class _Storage:
    def __init__(self, log): self.log = log
    def from_(self, bucket): self.log.append(("storage_from", bucket)); return self
    def remove(self, paths): self.log.append(("storage_remove", tuple(paths)))


class _Admin:
    def __init__(self, log): self.log = log
    def delete_user(self, uid): self.log.append(("admin_delete_user", uid))


class _Auth:
    def __init__(self, log): self.admin = _Admin(log)


class _FakeSupabase:
    def __init__(self):
        self.log = []
        self.storage = _Storage(self.log)
        self.auth = _Auth(self.log)

    def table(self, name): return _Q(self.log, name)


def test_delete_account_cascades_and_deletes_auth_user(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    fake = _FakeSupabase()
    monkeypatch.setattr(acct, "supabase", fake)
    client = TestClient(app)
    r = client.delete("/api/account")
    assert r.status_code == 204
    deleted = [e[1] for e in fake.log if e[0] == "delete"]
    for tbl in acct.USER_TABLES:
        assert tbl in deleted, f"missing delete for {tbl}"
    assert all(e[2] == "u1" for e in fake.log if e[0] == "delete")
    assert ("admin_delete_user", "u1") in fake.log
    assert "food_cache" not in deleted and "waitlist" not in deleted
    app.dependency_overrides.clear()


def test_delete_account_children_before_auth_user(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    fake = _FakeSupabase()
    monkeypatch.setattr(acct, "supabase", fake)
    client = TestClient(app)
    client.delete("/api/account")
    ops = [op for (op, *_rest) in fake.log]
    last_delete = max(i for i, op in enumerate(ops) if op == "delete")
    admin_idx = ops.index("admin_delete_user")
    assert last_delete < admin_idx
    order = [e[1] for e in fake.log if e[0] == "delete"]
    assert order.index("symptoms") < order.index("meals")  # child before parent
    app.dependency_overrides.clear()


def test_delete_account_requires_auth():
    client = TestClient(app)
    r = client.delete("/api/account")
    assert r.status_code in (401, 403)
