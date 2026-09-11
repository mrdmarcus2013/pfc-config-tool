"""Explicit checkbox Off is distinct from the legacy empty/default request."""

from contextlib import contextmanager
from types import SimpleNamespace

import oracledb
import pytest
from fastapi.testclient import TestClient

from backend.app.main import app, get_configuration_service
from backend.app.services.configuration import ConfigurationService
from backend.tests.test_configuration_response_validation import set_summary_value
from backend.tests.test_configuration_service import HASH, make_connection, request_kwargs
from backend.tests.test_configuration_transactions import DriverTrace, cleanup_events


EMPTY = {
    "cbsa": False, "fips": False, "care_location_value_code": False,
    "patient_entered_value_code": False, "covered_days_value_code": False,
}


def payload(operation, **changes):
    return {
        "payor_guid": request_kwargs()["payor_guid"], "plan_guid": "synthetic-plan",
        "audit_user": request_kwargs()["audit_user"], "selections": EMPTY.copy(),
        **({"expected_state_hash": HASH} if operation == "apply" else {}),
        **changes,
    }


@contextmanager
def service_client(connection_factory):
    app.dependency_overrides[get_configuration_service] = lambda: ConfigurationService(connection_factory)
    try:
        with TestClient(app) as client:
            yield client
    finally:
        app.dependency_overrides.pop(get_configuration_service, None)


@pytest.mark.parametrize("operation", ["preview", "apply"])
@pytest.mark.parametrize("behavior", [None, "INHERIT", "OFF"])
@pytest.mark.parametrize("cbsa", [False, True])
def test_api_preserves_empty_request_intent_and_forwards_exact_oracle_behavior(operation, behavior, cbsa):
    connection = make_connection(
        status="PREVIEW" if operation == "preview" else "APPLIED",
        display_label="Synthetic Value Codes result",
    )
    trace = DriverTrace(connection)
    body = payload(operation, selections={**EMPTY, "cbsa": cbsa})
    if behavior is not None:
        body["empty_selection_behavior"] = behavior

    with service_client(trace.connect) as client:
        response = client.post(f"/api/config/value-codes/{operation}", json=body)

    assert response.status_code == 200
    data = response.json()
    assert data["is_default"] is (not cbsa and behavior != "OFF")
    assert data["selections"] == body["selections"]
    assert data["display_summary"] == "Synthetic Value Codes result"
    assert "empty_selection_behavior" not in data
    binds = connection._cursor.binds
    assert binds["empty_selection_behavior"] == (behavior or "INHERIT")
    assert binds["plan_guid"] == "synthetic-plan"
    assert binds["expected_state_hash"] == (HASH if operation == "apply" else None)
    assert {key: binds[key] for key in EMPTY} == {
        key: "Y" if value else "N" for key, value in body["selections"].items()
    }
    execute = next(event for event in trace.events if event[0] == "execute")
    assert execute[1].count("p_empty_selection_behavior => :empty_selection_behavior") == 2
    assert connection._cursor.execute_count == 1
    assert connection.commits == (1 if operation == "apply" else 0)
    assert connection.rollbacks == (0 if operation == "apply" else 1)
    tail = ["commit" if operation == "apply" else "rollback", *cleanup_events(f"values_{operation}")]
    assert [event[0] for event in trace.events][-len(tail):] == tail


@pytest.mark.parametrize("operation", ["preview", "apply"])
def test_direct_legacy_service_call_defaults_empty_selection_to_inheritance(operation):
    connection = make_connection(status="PREVIEW" if operation == "preview" else "APPLIED")
    result = getattr(ConfigurationService(lambda: connection), f"value_codes_{operation}")(**payload(operation))
    assert result["is_default"] is True
    assert result["selections"] == EMPTY
    assert connection._cursor.binds["empty_selection_behavior"] == "INHERIT"


@pytest.mark.parametrize("operation", ["preview", "apply"])
@pytest.mark.parametrize("behavior", [None, "", "off", "DEFAULT", "OFF ", 1, True])
def test_invalid_empty_selection_behavior_is_rejected_before_database_access(operation, behavior):
    def unexpected_connection():
        raise AssertionError("Rejected request must never open Oracle")

    with service_client(unexpected_connection) as client:
        response = client.post(f"/api/config/value-codes/{operation}", json=payload(
            operation, empty_selection_behavior=behavior,
        ))
    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"] == ["body", "empty_selection_behavior"]


@pytest.mark.parametrize("operation", ["preview", "apply"])
@pytest.mark.parametrize("flags", [
    {**EMPTY, "fips": True},
    {**EMPTY, "care_location_value_code": True, "patient_entered_value_code": True},
])
def test_off_behavior_does_not_bypass_existing_capability_validation(operation, flags):
    def unexpected_connection():
        raise AssertionError("Invalid capability combination must never open Oracle")

    with service_client(unexpected_connection) as client:
        response = client.post(f"/api/config/value-codes/{operation}", json=payload(
            operation, selections=flags, empty_selection_behavior="OFF",
        ))
    assert response.status_code == 422


@pytest.mark.parametrize("failure", ["invalid_response", "stale_preview"])
def test_explicit_off_apply_retains_response_validation_and_stale_hash_rollback(failure):
    connection = make_connection(status="APPLIED")
    if failure == "invalid_response":
        set_summary_value(connection, "STATE_HASH", "invalid synthetic hash")
    else:
        connection._cursor.execute_error = oracledb.DatabaseError(SimpleNamespace(code=20036))
    with service_client(lambda: connection) as client:
        response = client.post("/api/config/value-codes/apply", json=payload(
            "apply", empty_selection_behavior="OFF",
        ))
    assert response.status_code == (500 if failure == "invalid_response" else 409)
    assert response.json()["error"]["category"] == (
        "application_failure" if failure == "invalid_response" else "stale_preview"
    )
    assert connection.commits == 0 and connection.rollbacks == 1 and connection.closed


def test_openapi_documents_legacy_default_only_on_change_requests():
    schemas = app.openapi()["components"]["schemas"]
    for model in ("ValueCodesChangeRequest", "ValueCodesApplyRequest"):
        definition = schemas[model]
        field = definition["properties"]["empty_selection_behavior"]
        assert field["enum"] == ["INHERIT", "OFF"]
        assert field["default"] == "INHERIT"
        assert "empty_selection_behavior" not in definition["required"]
    for model in ("ValueCodesCurrentRequest", "ValueCodesCurrentResponse", "ValueCodesChangeResponse"):
        assert "empty_selection_behavior" not in schemas[model]["properties"]
