import types
from app.services import knowledge


class _Query:
    def __init__(self, store, table):
        self.store, self.table = store, table
        self._op = None; self._payload = None; self._filters = []; self._order = None

    def insert(self, payload): self._op = "insert"; self._payload = payload; return self
    def select(self, cols): self._op = "select"; return self
    def update(self, payload): self._op = "update"; self._payload = payload; return self
    def delete(self): self._op = "delete"; return self
    def eq(self, col, val): self._filters.append((col, val)); return self
    def order(self, col, desc=False): self._order = (col, desc); return self

    def execute(self):
        self.store["calls"].append((self.table, self._op, self._payload, self._filters))
        # Stash last order info separately so new tests can assert on it without
        # widening the 4-tuple that existing tests unpack.
        if self._order is not None:
            self.store["last_order"] = (self.table, self._order)
        if self._op == "insert":
            row = dict(self._payload); row["id"] = "kb1"
            return types.SimpleNamespace(data=[row])
        if self._op == "select":
            return types.SimpleNamespace(data=self.store.get("rows", []))
        if self._op == "update":
            return types.SimpleNamespace(data=[{"id": self._filters[0][1], **self._payload}])
        return types.SimpleNamespace(data=[])  # delete


class _FakeSupabase:
    def __init__(self, store): self.store = store
    def table(self, name): return _Query(self.store, name)
    def rpc(self, fn, params):
        self.store["rpc"] = (fn, params)
        return types.SimpleNamespace(
            execute=lambda: types.SimpleNamespace(data=self.store.get("rpc_rows", [])))


def _setup(monkeypatch, store):
    monkeypatch.setattr(knowledge, "supabase", _FakeSupabase(store))
    monkeypatch.setattr(knowledge, "embed", lambda t: [0.5] * 3072)


def test_add_entry_embeds_and_strips_vector(monkeypatch):
    store = {"calls": []}; _setup(monkeypatch, store)
    row = knowledge.add_entry("Title", "body text", conditions=["gerd"])
    assert "content_embedding" not in row          # returned row is lightweight
    table, op, payload, _ = store["calls"][0]
    assert table == "knowledge_base" and op == "insert"
    assert payload["content_embedding"] == [0.5] * 3072
    assert payload["conditions"] == ["gerd"]
    assert payload["content"] == "body text"


def test_search_calls_rpc_with_right_args(monkeypatch):
    store = {"calls": [], "rpc_rows": [
        {"id": "kb1", "title": "X", "content": "c", "conditions": [], "similarity": 0.9}]}
    _setup(monkeypatch, store)
    rows = knowledge.search("acid reflux", k=3, conditions=["gerd"])
    fn, params = store["rpc"]
    assert fn == "match_knowledge"
    assert params["query_embedding"] == [0.5] * 3072
    assert params["match_count"] == 3
    assert params["filter_conditions"] == ["gerd"]
    assert rows[0]["title"] == "X"


def test_search_empty_conditions_passes_none(monkeypatch):
    store = {"calls": [], "rpc_rows": []}; _setup(monkeypatch, store)
    knowledge.search("q", conditions=[])
    assert store["rpc"][1]["filter_conditions"] is None


def test_search_swallows_errors(monkeypatch):
    def boom(_): raise RuntimeError("no api key")
    monkeypatch.setattr(knowledge, "embed", boom)
    monkeypatch.setattr(knowledge, "supabase", _FakeSupabase({"calls": []}))
    assert knowledge.search("q") == []


def test_format_context_block_and_empty():
    assert knowledge.format_context([]) == ""
    block = knowledge.format_context([{"title": "T", "content": "body"}])
    assert "Relevant current research" in block
    assert "- T: body" in block


def test_set_active_updates_row(monkeypatch):
    store = {"calls": []}; _setup(monkeypatch, store)
    out = knowledge.set_active("kb9", False)
    table, op, payload, filters = store["calls"][0]
    assert op == "update" and payload == {"active": False} and filters == [("id", "kb9")]
    assert out["active"] is False


def test_list_entries_selects_columns_ordered(monkeypatch):
    """list_entries() must SELECT from knowledge_base ordered by created_at desc."""
    sentinel_rows = [
        {"id": "kb2", "title": "B", "created_at": "2024-02-01"},
        {"id": "kb1", "title": "A", "created_at": "2024-01-01"},
    ]
    store = {"calls": [], "rows": sentinel_rows}
    _setup(monkeypatch, store)

    result = knowledge.list_entries()

    # One call was made to the knowledge_base table with a select op.
    assert len(store["calls"]) == 1
    table, op, _, _ = store["calls"][0]
    assert table == "knowledge_base"
    assert op == "select"

    # The call was ordered by created_at descending.
    order_table, (col, desc) = store["last_order"]
    assert order_table == "knowledge_base"
    assert col == "created_at"
    assert desc is True

    # Returns the data payload from the fake.
    assert result == sentinel_rows


def test_delete_entry_by_id(monkeypatch):
    """delete_entry(id) must issue a DELETE filtered by the given id."""
    store = {"calls": []}
    _setup(monkeypatch, store)

    knowledge.delete_entry("kb99")

    assert len(store["calls"]) == 1
    table, op, _, filters = store["calls"][0]
    assert table == "knowledge_base"
    assert op == "delete"
    assert ("id", "kb99") in filters
