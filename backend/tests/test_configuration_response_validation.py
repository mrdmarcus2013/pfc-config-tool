"""A rejected public response must not follow an already committed save."""

import pytest
from fastapi.testclient import TestClient

from backend.app.errors import ApiError
from backend.app.main import app, get_configuration_service
from backend.app.models import (
    ConfigurationResponse,
    LineOfBusinessChangeResponse,
    LineOfBusinessSaveResponse,
    RemarksChangeResponse,
    ValueCodesChangeResponse,
)
from backend.app.services.configuration import ConfigurationService
from backend.tests.test_configuration_service import HASH, request_kwargs
from backend.tests.test_configuration_transactions import DriverTrace, WRITES, cleanup_events, operation_case


RESPONSE_MODELS = {
    "option_apply": ConfigurationResponse,
    "values_apply": ValueCodesChangeResponse,
    "remarks_apply": RemarksChangeResponse,
    "lob_apply": LineOfBusinessChangeResponse,
    "lob_save": LineOfBusinessSaveResponse,
}


def result_cursor(connection, index=0):
    cursor = connection._cursor
    outputs = list(cursor._outputs) if hasattr(cursor, "_outputs") else [cursor._output]
    if hasattr(cursor, "_outputs"):
        cursor._outputs = iter(outputs)
    return outputs[index].getvalue()


def set_summary_value(connection, column, value):
    result = result_cursor(connection)
    index = [description[0] for description in result.description].index(column)
    row = list(result._rows[0])
    row[index] = value
    result._rows[0] = row


def assert_rejected_before_commit(operation, connection, call):
    trace = DriverTrace(connection)
    with pytest.raises(ApiError) as caught:
        call(ConfigurationService(trace.connect))
    assert caught.value.status_code == 500 and caught.value.category == "application_failure"
    assert connection.commits == 0 and connection.rollbacks == 1
    assert [event[0] for event in trace.events][-len(cleanup_events(operation)):] == cleanup_events(operation)
    assert connection.closed
    return caught.value


@pytest.mark.parametrize("operation", ["option_apply", "values_apply", "remarks_apply"])
def test_malformed_nested_change_rolls_back_before_commit(operation):
    connection, call = operation_case(operation)
    result_cursor(connection, 1)._rows = [(1, "KEEP", {"private": "invalid target"}, "81")]
    error = assert_rejected_before_commit(operation, connection, call)
    assert "private" not in error.message


@pytest.mark.parametrize("state_hash", ["G" * 64, "a" * 64])
def test_lob_hash_failing_public_contract_rolls_back_before_commit(state_hash):
    connection, call = operation_case("lob_apply")
    set_summary_value(connection, "PREVIEW_STATE_HASH", state_hash)
    assert_rejected_before_commit("lob_apply", connection, call)


@pytest.mark.parametrize("fault", ["missing_required_field", "invalid_status"])
def test_invalid_constructed_response_rolls_back_before_commit(monkeypatch, fault):
    original = ConfigurationService._response

    def malformed(summary, changes):
        response = original(summary, changes)
        if fault == "missing_required_field":
            response.pop("state_hash")
        else:
            response["status"] = "UNKNOWN"
        return response

    monkeypatch.setattr(ConfigurationService, "_response", staticmethod(malformed))
    connection, call = operation_case("option_apply")
    assert_rejected_before_commit("option_apply", connection, call)


def test_unserializable_response_rolls_back_before_commit():
    connection, call = operation_case("option_apply")
    set_summary_value(connection, "DISPLAY_LABEL", chr(0xD800))
    assert_rejected_before_commit("option_apply", connection, call)


def test_response_construction_exception_remains_safe_and_rolls_back(monkeypatch):
    def broken_response(summary, changes):
        raise RuntimeError("Private synthetic response construction detail")

    monkeypatch.setattr(ConfigurationService, "_response", staticmethod(broken_response))
    connection, call = operation_case("option_apply")
    error = assert_rejected_before_commit("option_apply", connection, call)
    assert error.message == "The configuration operation failed safely."


@pytest.mark.parametrize("operation", WRITES)
def test_valid_write_preserves_dict_response_and_commits_once(operation):
    connection, call = operation_case(operation)
    trace = DriverTrace(connection)
    response = call(ConfigurationService(trace.connect))
    assert isinstance(response, dict)
    assert RESPONSE_MODELS[operation].model_validate(response).model_dump() == response
    assert connection.commits == 1 and connection.rollbacks == 0 and connection.closed
    tail = ["commit", *cleanup_events(operation)]
    assert [event[0] for event in trace.events][-len(tail):] == tail


@pytest.mark.parametrize("operation", WRITES)
def test_cleanup_error_cannot_mask_valid_known_commit(operation, caplog):
    connection, call = operation_case(operation)
    trace = DriverTrace(connection, {"close:connection": RuntimeError("Synthetic close failure")})
    response = call(ConfigurationService(trace.connect))
    assert response["status"] == ("SAVED" if operation == "lob_save" else "APPLIED")
    assert connection.commits == 1 and connection.rollbacks == 0
    assert len(caplog.messages) == 1 and caplog.messages[0].endswith("connection close failed")


def test_api_returns_safe_error_without_committing_malformed_lob_response():
    connection, _ = operation_case("lob_apply")
    set_summary_value(connection, "PREVIEW_STATE_HASH", "G" * 64)
    service = ConfigurationService(lambda: connection)
    app.dependency_overrides[get_configuration_service] = lambda: service
    try:
        with TestClient(app, raise_server_exceptions=False) as client:
            response = client.post("/api/config/line-of-business/apply-change", json={
                "payor_guid": request_kwargs()["payor_guid"],
                "requested_line_of_business": "HOSPICE",
                "expected_state_hash": HASH,
                "audit_user": request_kwargs()["audit_user"],
            })
        assert connection.commits == 0 and connection.rollbacks == 1
        assert response.status_code == 500
        assert response.json() == {"error": {
            "category": "application_failure",
            "message": "The Line of Business operation failed safely.",
        }}
    finally:
        app.dependency_overrides.pop(get_configuration_service, None)
