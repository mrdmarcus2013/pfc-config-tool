from __future__ import annotations

from types import SimpleNamespace

import oracledb
import pytest
from fastapi.testclient import TestClient

from backend.app.errors import ApiError, translate_oracle_error
from backend.app.main import app, get_configuration_service
from backend.app.services.configuration import ConfigurationService


HASH = "A" * 64
BASE_REQUEST = {
    "payor_guid": "10000000-0000-0000-0000-0000000000A1",
    "plan_guid": None,
    "option_code": "PROVIDER_TAXONOMY_ON",
    "audit_user": "90000000-0000-0000-0000-000000000003",
}
SERVICE_FACILITY_OPTIONS = [
    "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
    "SERVICE_FACILITY_ALWAYS_ADDRESS_NO",
    "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES",
    "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO",
    "SERVICE_FACILITY_NEVER",
]
PUBLIC_OPTIONS = [
    "PROVIDER_TAXONOMY_ON",
    "PROVIDER_TAXONOMY_OFF",
    *SERVICE_FACILITY_OPTIONS,
]


class StubService:
    def health(self):
        return {"application": "ok", "oracle": "connected"}

    def list_options(self):
        return ConfigurationService().list_options()

    def preview(self, **request):
        return self._result("PREVIEW", request)

    def apply(self, **request):
        return self._result("APPLIED", request)

    @staticmethod
    def _result(status, request):
        is_service_facility = request["option_code"].startswith("SERVICE_FACILITY_")
        return {
            "status": status,
            "option_code": request["option_code"],
            "display_label": (
                "Always report service facility; report address"
                if is_service_facility
                else "Provider Taxonomy ON"
            ),
            "field_number": "77" if is_service_facility else "81",
            "state_hash": HASH,
            "change_count": 4,
            "summary": "4 configuration change(s) are ready for review.",
            "pfc_guid": "30000000-0000-0000-0000-0000000000A1",
            "debug_changes": (
                [
                    {
                        "operation_order": index,
                        "operation_code": "INSERT_HER",
                        "target_identifier": f"SYNTHETIC-SERVICE-TARGET-{index}",
                        "field_number": None,
                    }
                    for index in range(1, 4)
                ]
                if is_service_facility
                else []
            ),
        }


@pytest.fixture
def client():
    app.dependency_overrides[get_configuration_service] = StubService
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_health_reports_application_and_oracle(client):
    response = client.get("/api/health")

    assert response.status_code == 200
    assert response.json() == {"application": "ok", "oracle": "connected"}


def test_options_are_grouped_and_hide_database_details(client):
    response = client.get("/api/options")

    assert response.status_code == 200
    body = response.json()
    assert body["fields"][0]["field_number"] == "81"
    assert body["fields"][0]["field_label"] == "Provider Taxonomy"
    assert [item["display_label"] for item in body["fields"][0]["options"]] == [
        "Provider Taxonomy ON",
        "Provider Taxonomy OFF",
    ]
    assert body["fields"][1]["field_number"] == "77"
    assert body["fields"][1]["field_label"] == "Service Facility"
    service_options = body["fields"][1]["options"]
    assert [item["option_code"] for item in service_options] == SERVICE_FACILITY_OPTIONS
    assert [item["display_label"] for item in service_options] == [
        "Always report service facility; report address",
        "Always report service facility; do not report address",
        "Report service facility when care location is not HOME; report address",
        "Report service facility when care location is not HOME; do not report address",
        "Never report service facility; do not report address",
    ]
    assert "SERVICE_FACILITY_NEVER_ADDRESS_YES" not in response.text
    assert "sto_proc" not in response.text.lower()
    assert "return_1" not in response.text.lower()
    assert "record_type_code" not in response.text.lower()


def test_preview_validates_required_request_fields(client):
    request = dict(BASE_REQUEST)
    request.pop("audit_user")

    response = client.post("/api/config/preview", json=request)

    assert response.status_code == 422


@pytest.mark.parametrize("option_code", PUBLIC_OPTIONS)
def test_every_public_option_is_accepted_for_preview(client, option_code):
    response = client.post(
        "/api/config/preview",
        json={**BASE_REQUEST, "option_code": option_code},
    )

    assert response.status_code == 200
    assert response.json()["option_code"] == option_code


@pytest.mark.parametrize("option_code", SERVICE_FACILITY_OPTIONS)
def test_every_service_facility_option_is_accepted_for_apply(client, option_code):
    response = client.post(
        "/api/config/apply",
        json={
            **BASE_REQUEST,
            "option_code": option_code,
            "expected_state_hash": HASH,
        },
    )

    assert response.status_code == 200
    assert response.json()["option_code"] == option_code


@pytest.mark.parametrize("endpoint", ["preview", "apply"])
def test_unknown_service_facility_option_is_rejected(client, endpoint):
    request = {
        **BASE_REQUEST,
        "option_code": "SERVICE_FACILITY_NEVER_ADDRESS_YES",
    }
    if endpoint == "apply":
        request["expected_state_hash"] = HASH

    response = client.post(f"/api/config/{endpoint}", json=request)

    assert response.status_code == 422


def test_preview_returns_safe_summary(client):
    response = client.post("/api/config/preview", json=BASE_REQUEST)

    assert response.status_code == 200
    assert response.json()["status"] == "PREVIEW"
    assert response.json()["state_hash"] == HASH
    assert response.json()["field_number"] == "81"


def test_service_facility_preview_preserves_multi_target_details(client):
    response = client.post(
        "/api/config/preview",
        json={
            **BASE_REQUEST,
            "option_code": "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["option_code"] == "SERVICE_FACILITY_ALWAYS_ADDRESS_YES"
    assert body["field_number"] == "77"
    assert body["state_hash"] == HASH
    assert len(body["debug_changes"]) == 3
    assert {change["target_identifier"] for change in body["debug_changes"]} == {
        "SYNTHETIC-SERVICE-TARGET-1",
        "SYNTHETIC-SERVICE-TARGET-2",
        "SYNTHETIC-SERVICE-TARGET-3",
    }


def test_apply_requires_expected_state_hash(client):
    response = client.post("/api/config/apply", json=BASE_REQUEST)

    assert response.status_code == 422


@pytest.mark.parametrize("state_hash", ["A" * 63, "a" * 64, "G" * 64])
def test_apply_rejects_invalid_expected_state_hash(client, state_hash):
    response = client.post(
        "/api/config/apply",
        json={
            **BASE_REQUEST,
            "option_code": "SERVICE_FACILITY_NEVER",
            "expected_state_hash": state_hash,
        },
    )

    assert response.status_code == 422


def test_stale_preview_error_has_stable_api_shape():
    class StaleService(StubService):
        def apply(self, **request):
            raise ApiError(409, "stale_preview", "Preview again before applying the change.")

    app.dependency_overrides[get_configuration_service] = StaleService
    try:
        with TestClient(app) as test_client:
            response = test_client.post(
                "/api/config/apply",
                json={**BASE_REQUEST, "expected_state_hash": HASH},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 409
    assert response.json() == {
        "error": {
            "category": "stale_preview",
            "message": "Preview again before applying the change.",
        }
    }


def test_unknown_oracle_error_does_not_expose_credentials_or_sql():
    details = SimpleNamespace(
        code=12541,
        message="password=SYNTHETIC_TEST_SECRET SELECT secret FROM sensitive_table",
    )
    error = oracledb.DatabaseError(details)

    translated = translate_oracle_error(error, "preview")
    rendered = f"{translated.category} {translated.message}".lower()

    assert translated.status_code == 503
    assert "password" not in rendered
    assert "select" not in rendered
    assert "sensitive_table" not in rendered
