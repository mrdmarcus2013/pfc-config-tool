import pytest
from fastapi.testclient import TestClient

from backend.app.errors import ApiError
from backend.app.main import app, get_configuration_service
from backend.app.models import (
    ConfigurationOverviewResponse,
    CurrentConfigurationDisplay,
    CurrentConfigurationResponse,
    LineOfBusinessCurrentResponse,
    RemarksCurrentResponse,
    ValueCodeSelections,
    ValueCodesCurrentResponse,
)
from backend.app.services.configuration import ConfigurationService


@pytest.fixture
def resolved_field_states():
    return {
        "81": CurrentConfigurationResponse(
            status="RESOLVED",
            field_number="81",
            capability="provider-taxonomy",
            effective_option_code="PROVIDER_TAXONOMY_OFF",
            display=CurrentConfigurationDisplay(enabled=False),
            pfc_guid="synthetic-pfc",
        ).model_dump(),
        "39-41": ValueCodesCurrentResponse(
            configuration_status="RESOLVED",
            line_of_business="HOME_HEALTH",
            is_default=False,
            selections=ValueCodeSelections(cbsa=True),
            canonical_status="CANONICAL",
            display_summary="CBSA (inherited)",
            pfc_guid="synthetic-pfc",
        ).model_dump(),
        "80": RemarksCurrentResponse(
            configuration_status="RESOLVED",
            line_of_business="HOME_HEALTH",
            mode="DEFAULT",
            custom_remark=None,
            canonical_status="CANONICAL",
            display_summary="Default",
            pfc_guid="synthetic-pfc",
        ).model_dump(),
    }


def test_overview_preserves_other_fields_when_one_cannot_resolve(monkeypatch, resolved_field_states):
    service = ConfigurationService()
    lob = LineOfBusinessCurrentResponse(status="DEFINED", line_of_business="HOME_HEALTH")
    monkeypatch.setattr(service, "line_of_business_current", lambda **kwargs: lob.model_dump())
    calls = []

    def current(**kwargs):
        calls.append(kwargs)
        if kwargs["field_number"] == "77":
            raise ApiError(409, "ambiguous_source", "The source is ambiguous.")
        return resolved_field_states["81"]

    monkeypatch.setattr(service, "current", current)
    monkeypatch.setattr(service, "value_codes_current", lambda **kwargs: resolved_field_states["39-41"])
    monkeypatch.setattr(service, "remarks_current", lambda **kwargs: resolved_field_states["80"])
    result = service.overview(payor_guid="synthetic-payor", plan_guid="synthetic-plan")["fields"]
    assert result["77"]["status"] == "UNAVAILABLE"
    assert result["77"]["error"]["category"] == "ambiguous_source"
    assert all(result[field]["status"] == "RESOLVED" for field in ("81", "80", "39-41"))
    assert all(call["plan_guid"] == "synthetic-plan" for call in calls)
    # Partial failures must remain valid at the API response boundary too.
    ConfigurationOverviewResponse.model_validate({"fields": result})


def test_overview_api_requires_lob_without_reading_configuration(monkeypatch):
    service = ConfigurationService(lambda: (_ for _ in ()).throw(AssertionError("Unexpected database read")))
    lob = LineOfBusinessCurrentResponse(status="UNDEFINED", line_of_business=None)
    monkeypatch.setattr(service, "line_of_business_current", lambda **kwargs: lob.model_dump())
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
