from app.services import photo_pipeline as pp


def test_food_plate_happy_path(monkeypatch):
    rec = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg",
        "photo_type": "food_plate", "processing_status": "processing",
        "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"img")
    monkeypatch.setattr(pp.food_plate, "analyze_food_plate",
                        lambda data, ct: {"foods": [{"name": "egg"}], "source": "food_plate_vision"})
    monkeypatch.setattr(pp.photo_store, "set_result",
                        lambda u, p, d: rec.update({"result": d}))
    monkeypatch.setattr(pp.photo_store, "set_failed",
                        lambda u, p, m: rec.update({"failed": m}))
    pp.process_photo("p1", "u1")
    assert rec["result"]["foods"][0]["name"] == "egg"
    assert "failed" not in rec


def test_cache_short_circuits_when_already_complete(monkeypatch):
    calls = {"download": 0}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg", "photo_type": "food_plate",
        "processing_status": "complete", "extracted_data": {"foods": []}})
    monkeypatch.setattr(pp.photo_store, "download_bytes",
                        lambda path: calls.__setitem__("download", calls["download"] + 1) or b"x")
    monkeypatch.setattr(pp.photo_store, "set_result", lambda u, p, d: None)
    pp.process_photo("p1", "u1")
    assert calls["download"] == 0  # no re-download, no re-analyze


def test_unsupported_type_fails_cleanly(monkeypatch):
    rec = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg", "photo_type": "barcode",
        "processing_status": "processing", "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"img")
    monkeypatch.setattr(pp.photo_store, "set_failed", lambda u, p, m: rec.update({"failed": m}))
    monkeypatch.setattr(pp.photo_store, "set_result", lambda u, p, d: rec.update({"result": d}))
    pp.process_photo("p1", "u1")
    assert "not yet supported" in rec["failed"]
    assert "result" not in rec


def test_processor_exception_sets_failed(monkeypatch):
    rec = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg", "photo_type": "food_plate",
        "processing_status": "processing", "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"img")
    def _boom(data, ct): raise RuntimeError("vision down")
    monkeypatch.setattr(pp.food_plate, "analyze_food_plate", _boom)
    monkeypatch.setattr(pp.photo_store, "set_failed", lambda u, p, m: rec.update({"failed": m}))
    pp.process_photo("p1", "u1")
    assert "failed" in rec


def test_missing_row_is_noop(monkeypatch):
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: None)
    # must not raise
    pp.process_photo("nope", "u1")


def test_png_bytes_are_sent_as_png(monkeypatch):
    captured = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg",
        "photo_type": "food_plate", "processing_status": "processing",
        "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"\x89PNG\r\n\x1a\n rest")
    monkeypatch.setattr(pp.food_plate, "analyze_food_plate",
                        lambda data, ct: captured.update({"ct": ct}) or {"foods": [], "source": "food_plate_vision"})
    monkeypatch.setattr(pp.photo_store, "set_result", lambda u, p, d: None)
    pp.process_photo("p1", "u1")
    assert captured["ct"] == "image/png"


def test_jpeg_bytes_are_sent_as_jpeg(monkeypatch):
    captured = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg",
        "photo_type": "food_plate", "processing_status": "processing",
        "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"\xff\xd8\xff\xe0 rest")
    monkeypatch.setattr(pp.food_plate, "analyze_food_plate",
                        lambda data, ct: captured.update({"ct": ct}) or {"foods": [], "source": "food_plate_vision"})
    monkeypatch.setattr(pp.photo_store, "set_result", lambda u, p, d: None)
    pp.process_photo("p1", "u1")
    assert captured["ct"] == "image/jpeg"
