import os
import pytest

from app.main import app
from app.licensing import require_active_license


@pytest.fixture(autouse=True)
def _bypass_license_gate():
    # Existing endpoint tests assert behavior, not licensing — bypass the gate
    # suite-wide. Gate behavior is covered in isolation by test_license_gate_unit.py
    # (which builds its own FastAPI app and is unaffected by this override).
    app.dependency_overrides[require_active_license] = lambda: {"id": "u1", "email": "e"}
    yield
    app.dependency_overrides.pop(require_active_license, None)


@pytest.fixture(scope="session")
def api_base():
    return os.environ["API_BASE_URL"]

@pytest.fixture(scope="session")
def headers():
    return {"Authorization": f"Bearer {os.environ['TEST_JWT']}"}
