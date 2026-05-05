import os
import pytest

@pytest.fixture(scope="session")
def api_base():
    return os.environ["API_BASE_URL"]

@pytest.fixture(scope="session")
def headers():
    return {"Authorization": f"Bearer {os.environ['TEST_JWT']}"}
