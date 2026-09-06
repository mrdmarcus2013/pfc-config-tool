"""Characterize ordinary configuration lifecycles using synthetic driver failures."""

from types import SimpleNamespace

import oracledb
import pytest

from backend.app.database import DatabaseConfigurationError
from backend.app.errors import ApiError
from backend.app.services.configuration import ConfigurationService
from backend.tests.test_configuration_service import (
    HASH,
    Connection,
    CurrentProcedureCursor,
    ResultCursor,
    make_connection,
    make_context_connection,
    make_current_connection,
    make_lob_change_connection,
    make_remarks_current_connection,
    make_support_context_catalog_connection,
    make_value_codes_current_connection,
    request_kwargs,
)


OPERATIONS = (
    "option_preview", "option_apply", "option_current",
    "values_preview", "values_apply", "values_current",
    "remarks_preview", "remarks_apply", "remarks_current",
    "lob_preview", "lob_apply", "lob_current", "lob_save",
    "context", "catalog",
)
WRITES = ("option_apply", "values_apply", "remarks_apply", "lob_apply", "lob_save")
TWO_RESULTS = (
    "option_preview", "option_apply", "values_preview", "values_apply",
    "remarks_preview", "remarks_apply", "lob_preview", "lob_apply",
)


def operation_case(operation, status=None):
    request = request_kwargs()
    context = {"payor_guid": request["payor_guid"], "plan_guid": None}
    edit = {**context, "audit_user": request["audit_user"]}
    change_status = status or ("APPLIED" if operation in WRITES else "PREVIEW")
    if operation.startswith("option_"):
        mode = operation.removeprefix("option_")
        if mode == "current":
            return make_current_connection(), lambda service: service.current(**context, field_number="81")
        payload = {**request, **({"expected_state_hash": HASH} if mode == "apply" else {})}
        return make_connection(status=change_status), lambda service: getattr(service, mode)(**payload)
    if operation.startswith("values_"):
        mode = operation.removeprefix("values_")
        if mode == "current":
            return make_value_codes_current_connection(), lambda service: service.value_codes_current(**context)
        selections = dict(cbsa=True, fips=False, care_location_value_code=False,
                          patient_entered_value_code=False, covered_days_value_code=False)
        payload = {**edit, "selections": selections,
                   **({"expected_state_hash": HASH} if mode == "apply" else {})}
        return make_connection(status=change_status), lambda service: getattr(service, f"value_codes_{mode}")(**payload)
    if operation.startswith("remarks_"):
        mode = operation.removeprefix("remarks_")
        if mode == "current":
            return make_remarks_current_connection(), lambda service: service.remarks_current(**context)
        payload = {**edit, "mode": "CUSTOM", "custom_remark": "Synthetic remark",
                   **({"expected_state_hash": HASH} if mode == "apply" else {})}
        return make_connection(status=change_status), lambda service: getattr(service, f"remarks_{mode}")(**payload)
    if operation in {"lob_preview", "lob_apply"}:
        mode = operation.removeprefix("lob_")
        payload = {"payor_guid": context["payor_guid"], "requested_line_of_business": "HOSPICE"}
        if mode == "apply":
            payload.update(audit_user=edit["audit_user"], expected_state_hash=HASH)
        lob_status = status or ("APPLIED" if mode == "apply" else "CHANGES_REQUIRED")
        return make_lob_change_connection(status=lob_status), lambda service: getattr(service, f"line_of_business_{mode}_change")(**payload)
    if operation in {"lob_current", "lob_save"}:
        is_save = operation == "lob_save"
        result = ResultCursor(["STATUS", "LINE_OF_BUSINESS"],
                              [[status or ("SAVED" if is_save else "UNDEFINED"), "HOME_HEALTH" if is_save else None]])
        payload = {"payor_guid": context["payor_guid"]}
        if is_save:
            payload.update(line_of_business="HOME_HEALTH", audit_user=edit["audit_user"])
        return Connection(CurrentProcedureCursor(result)), lambda service: getattr(service, f"line_of_business_{'save' if is_save else 'current'}")(**payload)
    if operation == "context":
        return make_context_connection(), lambda service: service.configuration_context(**context)
    if operation == "catalog":
        return make_support_context_catalog_connection(), lambda service: service.list_support_payor_contexts()
    raise AssertionError(f"Unknown test operation: {operation}")


class DriverTrace:
    """Wrap existing synthetic fixtures and inject faults at observable driver calls."""

    def __init__(self, connection, faults=None):
        self.connection = connection
        self.faults = faults or {}
        self.events = []

    def event(self, name, *details):
        self.events.append((name, *details))
        if name in self.faults:
            raise self.faults[name]

    def connect(self):
        self.event("connect")
        return self

    def cursor(self):
        self.event("cursor")
        return TracedCursor(self, self.connection.cursor())

    def commit(self):
        self.event("commit")
        self.connection.commit()

    def rollback(self):
        self.event("rollback")
        self.connection.rollback()

    def close(self):
        self.event("close:connection")
        self.connection.close()


class TracedCursor:
    def __init__(self, trace, cursor, name="procedure"):
        self.trace, self.cursor, self.name = trace, cursor, name
        self.variable_count = 0

    @property
    def description(self):
        return self.cursor.description

    def var(self, data_type, **kwargs):
        self.variable_count += 1
        number = self.variable_count
        self.trace.event(f"var:{number}", str(data_type), kwargs)
        output = self.cursor.var(data_type, **kwargs)

        def getvalue():
            self.trace.event(f"getvalue:{number}")
            value = output.getvalue()
            return TracedCursor(self.trace, value, f"result{number}") if hasattr(value, "fetchall") else value

        return SimpleNamespace(getvalue=getvalue, trace_number=number)

    def execute(self, sql, **binds):
        stable_binds = {key: f"out:{value.trace_number}" if hasattr(value, "trace_number") else value
                        for key, value in binds.items()}
        self.trace.event("execute", sql, stable_binds)
        self.cursor.execute(sql, **binds)

    def fetchall(self):
        self.trace.event(f"fetchall:{self.name}")
        return self.cursor.fetchall()

    def close(self):
        self.trace.event(f"close:{self.name}")
        self.cursor.close()


def run_case(operation, faults=None, status=None, service_class=ConfigurationService):
    connection, call = operation_case(operation, status)
    trace = DriverTrace(connection, faults)
    try:
        result = call(service_class(trace.connect))
    except ApiError as exc:
        result = exc
    return trace, result


def cleanup_events(operation):
    results = ["close:result2", "close:result1"] if operation in TWO_RESULTS else (
        [] if operation in {"context", "catalog"} else ["close:result1"])
    return [*results, "close:procedure", "close:connection"]


@pytest.mark.parametrize("operation", OPERATIONS)
def test_success_preserves_transaction_and_reverse_cursor_cleanup_order(operation):
    trace, result = run_case(operation)
    assert not isinstance(result, Exception)
    names = [event[0] for event in trace.events]
    disposition = "commit" if operation in WRITES else "rollback"
    tail = [disposition, *cleanup_events(operation)]
    assert names[-len(tail):] == tail
    assert names.count("execute") == 1
    assert names.count(disposition) == 1
    assert ("rollback" if disposition == "commit" else "commit") not in names


@pytest.mark.parametrize("operation", TWO_RESULTS)
def test_no_change_retains_each_operations_existing_commit_policy(operation):
    trace, result = run_case(operation, status="NO_CHANGE")
    assert result["status"] == "NO_CHANGE"
    assert ("commit",) in trace.events if operation in WRITES else ("rollback",) in trace.events


@pytest.mark.parametrize("operation", [*TWO_RESULTS, "lob_save"])
def test_invalid_status_rolls_back_before_any_commit(operation):
    trace, result = run_case(operation, status="INVALID")
    assert isinstance(result, ApiError) and result.category == "application_failure"
    names = [event[0] for event in trace.events]
    assert "commit" not in names
    assert names[-1 - len(cleanup_events(operation)):] == ["rollback", *cleanup_events(operation)]


@pytest.mark.parametrize("operation", OPERATIONS)
@pytest.mark.parametrize("failure", [
    ApiError(409, "synthetic_blocker", "Synthetic blocker."),
    oracledb.DatabaseError(SimpleNamespace(code=20036)),
    DatabaseConfigurationError("Synthetic missing setting"),
    RuntimeError("Synthetic adapter failure"),
])
def test_execution_errors_roll_back_and_preserve_error_policy(operation, failure):
    trace, result = run_case(operation, faults={"execute": failure})
    assert isinstance(result, ApiError)
    expected = "synthetic_blocker" if isinstance(failure, ApiError) else (
        "stale_preview" if isinstance(failure, oracledb.DatabaseError) else (
            "database_failure" if isinstance(failure, DatabaseConfigurationError) else "application_failure"))
    assert result.category == expected
    if isinstance(failure, ApiError):
        assert result is failure
    if isinstance(failure, DatabaseConfigurationError):
        assert result.__cause__ is failure
    assert [event[0] for event in trace.events][-3:] == ["rollback", "close:procedure", "close:connection"]
    assert not trace.connection.commits


@pytest.mark.parametrize("failure_at,expected_tail", [
    ("getvalue:2", ["rollback", "close:result1", "close:procedure", "close:connection"]),
    ("fetchall:result2", ["rollback", "close:result2", "close:result1", "close:procedure", "close:connection"]),
])
def test_partial_result_failure_closes_only_captured_cursors(failure_at, expected_tail):
    trace, result = run_case("option_apply", faults={failure_at: RuntimeError("Synthetic output failure")})
    assert isinstance(result, ApiError) and result.category == "application_failure"
    assert [event[0] for event in trace.events][-len(expected_tail):] == expected_tail
    assert not trace.connection.commits


@pytest.mark.parametrize("operation", WRITES)
def test_commit_failure_attempts_rollback_then_closes_every_captured_cursor(operation):
    trace, result = run_case(operation, faults={"commit": oracledb.DatabaseError(SimpleNamespace(code=3113))})
    assert isinstance(result, ApiError) and result.category == "database_failure"
    tail = ["commit", "rollback", *cleanup_events(operation)]
    assert [event[0] for event in trace.events][-len(tail):] == tail


def test_cleanup_failures_preserve_existing_application_error(caplog):
    blocker = ApiError(409, "synthetic_blocker", "Keep this error.")
    trace, result = run_case("option_apply", faults={
        "execute": blocker, "rollback": RuntimeError("Synthetic rollback failure"),
        "close:procedure": RuntimeError("Synthetic cursor close failure"),
        "close:connection": RuntimeError("Synthetic connection close failure"),
    })
    assert result is blocker
    assert [event[0] for event in trace.events][-3:] == ["rollback", "close:procedure", "close:connection"]
    assert caplog.messages == [
        "Oracle rollback failed while handling an operation error",
        "Oracle procedure cursor close failed",
        "Oracle procedure connection close failed",
    ]


def test_read_rollback_failure_retries_rollback_then_preserves_adapter_error(caplog):
    trace, result = run_case("option_preview", faults={"rollback": RuntimeError("Synthetic rollback failure")})
    assert isinstance(result, ApiError) and result.message == "The configuration operation failed safely."
    assert [event[0] for event in trace.events].count("rollback") == 2
    assert caplog.messages == [
        "Oracle rollback failed while handling an operation error",
        "Unexpected preview adapter failure (RuntimeError)",
    ]


@pytest.mark.parametrize("operation", ["option_preview", "option_apply"])
def test_close_failures_do_not_replace_successful_result(operation, caplog):
    trace, result = run_case(operation, faults={
        event: RuntimeError("Synthetic close failure") for event in cleanup_events(operation)
    })
    assert result["status"] == ("APPLIED" if operation in WRITES else "PREVIEW")
    assert [event[0] for event in trace.events][-4:] == cleanup_events(operation)
    assert caplog.messages == [
        "Oracle changes cursor close failed", "Oracle summary cursor close failed",
        "Oracle procedure cursor close failed", "Oracle procedure connection close failed",
    ]


@pytest.mark.parametrize("failure_at,events", [
    ("connect", ["connect"]),
    ("cursor", ["connect", "cursor", "rollback", "close:connection"]),
])
def test_acquisition_failures_clean_up_only_acquired_resources(failure_at, events):
    trace, result = run_case("option_apply", faults={failure_at: DatabaseConfigurationError("Synthetic setup failure")})
    assert isinstance(result, ApiError) and result.category == "database_failure"
    assert [event[0] for event in trace.events] == events
