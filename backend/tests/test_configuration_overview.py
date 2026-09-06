from fastapi.testclient import TestClient

from backend.app.errors import ApiError
from backend.app.main import app, get_configuration_service
from backend.app.services.configuration import ConfigurationService


def test_overview_preserves_other_fields_when_one_cannot_resolve(monkeypatch):
    service = ConfigurationService()
    monkeypatch.setattr(service, "line_of_business_current", lambda **kwargs: {"status": "DEFINED"})
    calls = []

    def current(**kwargs):
        calls.append(kwargs)
        if kwargs["field_number"] == "77":
            raise ApiError(409, "ambiguous_source", "The source is ambiguous.")
        return {"effective_option_code": "PROVIDER_TAXONOMY_OFF"}

    monkeypatch.setattr(service, "current", current)
    monkeypatch.setattr(service, "value_codes_current", lambda **kwargs: {"display_summary": "CBSA (inherited)"})
    monkeypatch.setattr(service, "remarks_current", lambda **kwargs: {"mode": "STANDARD"})
    result = service.overview(payor_guid="synthetic-payor", plan_guid="synthetic-plan")["fields"]
    assert result["77"]["status"] == "UNAVAILABLE"
    assert result["77"]["error"]["category"] == "ambiguous_source"
    assert all(result[field]["status"] == "RESOLVED" for field in ("81", "80", "39-41"))
    assert all(call["plan_guid"] == "synthetic-plan" for call in calls)


def test_overview_api_requires_lob_without_reading_configuration(monkeypatch):
    service = ConfigurationService(lambda: (_ for _ in ()).throw(AssertionError("Unexpected database read")))
    monkeypatch.setattr(service, "line_of_business_current", lambda **kwargs: {"status": "NOT_DEFINED"})
    app.dependency_overrides[get_configuration_service] = lambda: service
    try:
        response = TestClient(app).post("/api/config/overview", json={
            "payor_guid": "10000000-0000-0000-0000-0000000000A1", "plan_guid": None,
        })
        assert response.status_code == 200
        fields = response.json()["fields"]
        assert set(fields) == {"77", "81", "80", "39-41"}
        assert all(item["status"] == "LOB_REQUIRED" and item["current"] is None for item in fields.values())
    finally:
        app.dependency_overrides.pop(get_configuration_service, None)
