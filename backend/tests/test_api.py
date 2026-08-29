from __future__ import annotations

from types import SimpleNamespace

import oracledb
import pytest
from fastapi.testclient import TestClient

from backend.app.errors import ApiError, translate_oracle_error
from backend.app.main import app, get_configuration_service


HASH = "A" * 64
BASE_REQUEST = {
    "payor_guid": "10000000-0000-0000-0000-0000000000A1",
    "plan_guid": None,
    "option_code": "PROVIDER_TAXONOMY_ON",
    "audit_user": "90000000-0000-0000-0000-000000000003",
}


class StubService:
    def health(self):
        return {"application": "ok", "oracle": "connected"}

    def list_options(self):
        return {
            "fields": [
                {
                    "field_number": "81",
                    "field_label": "Provider Taxonomy",
                    "options": [
                        {
                            "option_code": "PROVIDER_TAXONOMY_ON",
                            "display_label": "Provider Taxonomy ON",
                        },
                        {
                            "option_code": "PROVIDER_TAXONOMY_OFF",
                            "display_label": "Provider Taxonomy OFF",
                        },
                    ],
                }
            ]
        }

    def preview(self, **request):
        return self._result("PREVIEW", request)

    def apply(self, **request):
        return self._result("APPLIED", request)

    @staticmethod
    def _result(status, request):
        return {
            "status": status,
            "option_code": request["option_code"],
            "display_label": "Provider Taxonomy ON",
            "field_number": "81",
            "state_hash": HASH,
            "change_count": 4,
            "summary": "4 configuration change(s) are ready for review.",
            "pfc_guid": "30000000-0000-0000-0000-0000000000A1",
            "debug_changes": [],
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
    assert "sto_proc" not in response.text.lower()
    assert "return_1" not in response.text.lower()


def test_preview_validates_required_request_fields(client):
    request = dict(BASE_REQUEST)
    request.pop("audit_user")

    response = client.post("/api/config/preview", json=request)

    assert response.status_code == 422


def test_service_facility_is_not_yet_publicly_invocable(client):
    preview_response = client.post(
        "/api/config/preview",
        json={
            **BASE_REQUEST,
            "option_code": "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
        },
    )
    apply_response = client.post(
        "/api/config/apply",
        json={
            **BASE_REQUEST,
            "option_code": "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
            "expected_state_hash": HASH,
        },
    )

    assert preview_response.status_code == 422
    assert apply_response.status_code == 422


def test_preview_returns_safe_summary(client):
    response = client.post("/api/config/preview", json=BASE_REQUEST)

    assert response.status_code == 200
    assert response.json()["status"] == "PREVIEW"
    assert response.json()["state_hash"] == HASH
    assert response.json()["field_number"] == "81"


def test_apply_requires_expected_state_hash(client):
    response = client.post("/api/config/apply", json=BASE_REQUEST)

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
