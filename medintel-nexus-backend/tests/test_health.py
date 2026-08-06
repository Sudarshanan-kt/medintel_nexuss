from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_patients_me_requires_auth() -> None:
    response = client.get("/api/v1/patients/me")
    assert response.status_code == 401
    assert "error" in response.json()
