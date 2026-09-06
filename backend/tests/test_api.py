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

    def list_support_payor_contexts(self):
        return {"contexts": [
            {
                "payor_guid": "synthetic-payor-1",
                "payor_name": "Synthetic Payor One",
                "payor_id": "SYN-ONE",
                "plan_guid": None,
            },
            {
                "payor_guid": "synthetic-payor-2",
                "payor_name": "Synthetic Payor Two",
                "payor_id": "SYN-TWO",
                "plan_guid": "synthetic-plan-2",
            },
        ]}

    def configuration_context(self, **request):
        return {
            "status": "RESOLVED",
            "payor_guid": request["payor_guid"],
            "plan_guid": request["plan_guid"],
            "pfc_guid": "30000000-0000-0000-0000-0000000000A1",
            "billing_form_code": "837I_5010",
            "form_template_guid": "50000000-0000-0000-0000-0000000000A1",
            "user_form_template_guid": "60000000-0000-0000-0000-0000000000A1",
        "form_template_name": "Home Health",
        "user_form_template_name": "Provider Taxonomy On",
        }

    def preview(self, **request):
        return self._result("PREVIEW", request)

    def current(self, **request):
        is_service_facility = request["field_number"] == "77"
        return {
            "status": "RESOLVED",
            "field_number": request["field_number"],
            "capability": "service-facility" if is_service_facility else "provider-taxonomy",
            "effective_option_code": (
                "SERVICE_FACILITY_NEVER" if is_service_facility else "PROVIDER_TAXONOMY_OFF"
            ),
            "display": (
                {"mode": "NEVER", "report_address": "N", "enabled": None}
                if is_service_facility
                else {"mode": None, "report_address": None, "enabled": False}
            ),
            "pfc_guid": "30000000-0000-0000-0000-0000000000A1",
            "canonical": True,
        }

    def apply(self, **request):
        return self._result("APPLIED", request)

    def line_of_business_current(self, **request):
        return {"status": "UNDEFINED", "line_of_business": None}

    def line_of_business_save(self, **request):
        return {"status": "SAVED", "line_of_business": request["line_of_business"]}

    def line_of_business_preview_change(self, **request):
        return self._lob_change("CHANGES_REQUIRED", request)

    def line_of_business_apply_change(self, **request):
        return self._lob_change("APPLIED", request)

    def value_codes_current(self, **request):
        return {
            "configuration_status": "RESOLVED", "line_of_business": "HOME_HEALTH",
            "is_default": True, "selections": value_code_selections(),
            "canonical_status": "INHERITED", "display_summary": "Default",
            "pfc_guid": "30000000-0000-0000-0000-0000000000A1", "debug": {},
        }

    def value_codes_preview(self, **request):
        return self._value_codes_result("PREVIEW", request)

    def value_codes_apply(self, **request):
        return self._value_codes_result("APPLIED", request)

    def remarks_current(self, **request):
        return {
            "configuration_status": "RESOLVED",
            "line_of_business": "HOME_HEALTH",
            "mode": "DEFAULT",
            "custom_remark": None,
            "canonical_status": "INHERITED",
            "display_summary": "Default",
            "pfc_guid": "30000000-0000-0000-0000-0000000000A1",
            "debug": {},
        }

    def remarks_preview(self, **request):
        return self._remarks_result("PREVIEW", request)

    def remarks_apply(self, **request):
        return self._remarks_result("APPLIED", request)

    @staticmethod
    def _remarks_result(status, request):
        return {
            "status": status,
            "mode": request["mode"],
            "custom_remark": request["custom_remark"],
            "display_summary": (
                "Default" if request["mode"] == "DEFAULT" else "Custom remark"
            ),
            "state_hash": HASH,
            "change_count": 1,
            "summary": "1 configuration change is ready for review.",
            "pfc_guid": "30000000-0000-0000-0000-0000000000A1",
            "debug_changes": [],
        }

    @staticmethod
    def _value_codes_result(status, request):
        selections = request["selections"]
        return {"status": status, "is_default": not any(selections.values()),
                "selections": selections,
                "display_summary": "Default" if not any(selections.values()) else "CBSA",
                "state_hash": HASH, "change_count": 1,
                "summary": "1 configuration change(s) is ready for review.",
                "pfc_guid": "30000000-0000-0000-0000-0000000000A1",
                "debug_changes": []}

    @staticmethod
    def _lob_change(status, request):
        return {
            "status": status,
            "changes_required": status != "NO_CHANGE",
            "current_line_of_business": "HOME_HEALTH",
            "requested_line_of_business": request["requested_line_of_business"],
            "managed_target_count": 4,
            "affected_managed_target_count": 2,
            "managed_her_count": 3,
            "managed_hef_count": 9,
            "preview_state_hash": HASH,
            "summary": "2 customized claim-field components will be reset.",
            "debug_targets": [],
        }

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


def value_code_selections(**overrides):
    return {"cbsa": False, "fips": False,
            "care_location_value_code": False,
            "patient_entered_value_code": False,
            "covered_days_value_code": False, **overrides}


def test_health_reports_application_and_oracle(client):
    response = client.get("/api/health")

    assert response.status_code == 200
    assert response.json() == {"application": "ok", "oracle": "connected"}


def test_support_payor_context_catalog_preserves_database_pairs(client):
    response = client.get("/api/support/payor-contexts")

    assert response.status_code == 200
    assert response.json() == {"contexts": [
        {
            "payor_guid": "synthetic-payor-1",
            "payor_name": "Synthetic Payor One",
            "payor_id": "SYN-ONE",
            "plan_guid": None,
            "plan_name": None,
        },
        {
            "payor_guid": "synthetic-payor-2",
            "payor_name": "Synthetic Payor Two",
            "payor_id": "SYN-TWO",
            "plan_guid": "synthetic-plan-2",
            "plan_name": None,
        },
    ]}


def test_line_of_business_endpoints_have_typed_payor_level_contracts(client):
    payor = BASE_REQUEST["payor_guid"]
    current = client.post("/api/config/line-of-business/current", json={"payor_guid": payor})
    assert current.status_code == 200
    assert current.json() == {"status": "UNDEFINED", "line_of_business": None}

    saved = client.post("/api/config/line-of-business/save", json={
        "payor_guid": payor,
        "line_of_business": "HOME_HEALTH",
        "audit_user": BASE_REQUEST["audit_user"],
    })
    assert saved.status_code == 200
    assert saved.json()["line_of_business"] == "HOME_HEALTH"

    preview = client.post("/api/config/line-of-business/preview-change", json={
        "payor_guid": payor, "requested_line_of_business": "HOSPICE",
    })
    assert preview.status_code == 200
    assert preview.json()["preview_state_hash"] == HASH
    assert preview.json()["affected_managed_target_count"] == 2

    applied = client.post("/api/config/line-of-business/apply-change", json={
        "payor_guid": payor,
        "requested_line_of_business": "HOSPICE",
        "expected_state_hash": HASH,
        "audit_user": BASE_REQUEST["audit_user"],
    })
    assert applied.status_code == 200
    assert applied.json()["status"] == "APPLIED"


@pytest.mark.parametrize("path,payload", [
    ("/api/config/line-of-business/save", {"line_of_business": "MEDICARE", "audit_user": BASE_REQUEST["audit_user"]}),
    ("/api/config/line-of-business/preview-change", {"requested_line_of_business": "MEDICARE"}),
    ("/api/config/line-of-business/apply-change", {"requested_line_of_business": "MEDICARE", "expected_state_hash": HASH, "audit_user": BASE_REQUEST["audit_user"]}),
])
def test_line_of_business_rejects_arbitrary_values(client, path, payload):
    response = client.post(path, json={"payor_guid": BASE_REQUEST["payor_guid"], **payload})
    assert response.status_code == 422


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


def test_configuration_context_exposes_resolved_guids_without_audit_data(client):
    request = {
        "payor_guid": BASE_REQUEST["payor_guid"],
        "plan_guid": "40000000-0000-0000-0000-0000000000A1",
    }
    response = client.post("/api/config/context", json=request)

    assert response.status_code == 200
    assert response.json() == {
        "status": "RESOLVED",
        "payor_guid": request["payor_guid"],
        "plan_guid": request["plan_guid"],
        "pfc_guid": "30000000-0000-0000-0000-0000000000A1",
        "billing_form_code": "837I_5010",
        "form_template_guid": "50000000-0000-0000-0000-0000000000A1",
        "user_form_template_guid": "60000000-0000-0000-0000-0000000000A1",
        "form_template_name": "Home Health",
        "user_form_template_name": "Provider Taxonomy On",
    }

    rejected = client.post("/api/config/context", json={**request, "audit_user": "extra"})
    assert rejected.status_code == 422


def test_preview_validates_required_request_fields(client):
    request = dict(BASE_REQUEST)
    request.pop("audit_user")

    response = client.post("/api/config/preview", json=request)

    assert response.status_code == 422


@pytest.mark.parametrize("field_number", ["77", "81"])
def test_current_configuration_accepts_supported_fields(client, field_number):
    response = client.post(
        "/api/config/current",
        json={
            "payor_guid": BASE_REQUEST["payor_guid"],
            "plan_guid": None,
            "field_number": field_number,
        },
    )

    assert response.status_code == 200
    assert response.json()["status"] == "RESOLVED"
    assert response.json()["field_number"] == field_number


def test_current_configuration_rejects_unsupported_field(client):
    response = client.post(
        "/api/config/current",
        json={
            "payor_guid": BASE_REQUEST["payor_guid"],
            "plan_guid": None,
            "field_number": "78",
        },
    )

    assert response.status_code == 422


def test_value_codes_uses_structured_contract_without_recipe_ids(client):
    base = {"payor_guid": BASE_REQUEST["payor_guid"], "plan_guid": None}
    current = client.post("/api/config/value-codes/current", json=base)
    assert current.status_code == 200
    assert current.json()["is_default"] is True
    assert current.json()["selections"] == value_code_selections()
    assert "recipe" not in current.text.lower()

    preview = client.post("/api/config/value-codes/preview", json={**base,
        "selections": value_code_selections(cbsa=True),
        "audit_user": BASE_REQUEST["audit_user"]})
    assert preview.status_code == 200
    assert preview.json()["display_summary"] == "CBSA"
    applied = client.post("/api/config/value-codes/apply", json={**base,
        "selections": value_code_selections(cbsa=True),
        "audit_user": BASE_REQUEST["audit_user"], "expected_state_hash": HASH})
    assert applied.status_code == 200
    assert applied.json()["status"] == "APPLIED"
    assert "HOME_HEALTH_CBSA" not in applied.text


def test_remarks_uses_structured_contract_and_round_trips_custom_text(client):
    base = {"payor_guid": BASE_REQUEST["payor_guid"], "plan_guid": None}
    current = client.post("/api/config/remarks/current", json=base)
    assert current.status_code == 200
    assert current.json()["mode"] == "DEFAULT"
    assert current.json()["custom_remark"] is None

    custom_text = "Call provider before processing"
    preview = client.post("/api/config/remarks/preview", json={
        **base,
        "mode": "CUSTOM",
        "custom_remark": custom_text,
        "audit_user": BASE_REQUEST["audit_user"],
    })
    assert preview.status_code == 200
    assert preview.json()["custom_remark"] == custom_text
    assert "option_code" not in preview.json()

    applied = client.post("/api/config/remarks/apply", json={
        **base,
        "mode": "CUSTOM",
        "custom_remark": custom_text,
        "audit_user": BASE_REQUEST["audit_user"],
        "expected_state_hash": HASH,
    })
    assert applied.status_code == 200
    assert applied.json()["custom_remark"] == custom_text
    assert "__PFC_REMARKS" not in applied.text


@pytest.mark.parametrize("custom_remark", [None, "", "   ", "X" * 101])
def test_custom_remarks_reject_blank_or_over_limit_text(client, custom_remark):
    response = client.post("/api/config/remarks/preview", json={
        "payor_guid": BASE_REQUEST["payor_guid"],
        "plan_guid": None,
        "mode": "CUSTOM",
        "custom_remark": custom_remark,
        "audit_user": BASE_REQUEST["audit_user"],
    })
    assert response.status_code == 422


def test_remarks_accepts_exact_limit_and_trims_boundary_whitespace(client):
    response = client.post("/api/config/remarks/preview", json={
        "payor_guid": BASE_REQUEST["payor_guid"],
        "plan_guid": None,
        "mode": "CUSTOM",
        "custom_remark": f"  {'X' * 100}  ",
        "audit_user": BASE_REQUEST["audit_user"],
    })
    assert response.status_code == 200
    assert response.json()["custom_remark"] == "X" * 100


def test_default_remarks_reject_nonblank_custom_text(client):
    response = client.post("/api/config/remarks/preview", json={
        "payor_guid": BASE_REQUEST["payor_guid"],
        "plan_guid": None,
        "mode": "DEFAULT",
        "custom_remark": "Do not silently ignore this",
        "audit_user": BASE_REQUEST["audit_user"],
    })
    assert response.status_code == 422


@pytest.mark.parametrize("selections", [
    value_code_selections(fips=True),
    value_code_selections(care_location_value_code=True,
                          patient_entered_value_code=True),
    value_code_selections(care_location_value_code=True,
                          patient_entered_value_code=True,
                          covered_days_value_code=True),
])
def test_value_codes_rejects_invalid_structured_combinations(client, selections):
    response = client.post("/api/config/value-codes/preview", json={
        "payor_guid": BASE_REQUEST["payor_guid"], "plan_guid": None,
        "selections": selections, "audit_user": BASE_REQUEST["audit_user"]})
    assert response.status_code == 422


@pytest.mark.parametrize("selections", [
    value_code_selections(patient_entered_value_code=True),
    value_code_selections(patient_entered_value_code=True,
                          covered_days_value_code=True),
    value_code_selections(covered_days_value_code=True),
])
def test_value_codes_accepts_patient_entered_without_vc80_and_independent_vc80(
    client, selections,
):
    response = client.post("/api/config/value-codes/preview", json={
        "payor_guid": BASE_REQUEST["payor_guid"], "plan_guid": None,
        "selections": selections, "audit_user": BASE_REQUEST["audit_user"]})
    assert response.status_code == 200
    assert response.json()["selections"] == selections


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


@pytest.mark.parametrize(
    ("code", "status_code", "category"),
    [
        (20010, 404, "configuration_not_found"),
        (20011, 409, "ambiguous_target"),
        (20020, 409, "source_not_found"),
        (20021, 409, "ambiguous_source"),
        (20012, 409, "invalid_inherited_configuration"),
        (20041, 409, "current_state_unsupported"),
    ],
)
def test_expected_current_state_oracle_errors_map_safely(code, status_code, category):
    details = SimpleNamespace(code=code, message="raw Oracle implementation detail")
    translated = translate_oracle_error(oracledb.DatabaseError(details), "current")

    assert translated.status_code == status_code
    assert translated.category == category
    assert "oracle" not in translated.message.lower()
    assert "implementation" not in translated.message.lower()
