from __future__ import annotations

from types import SimpleNamespace

import oracledb
import pytest

from backend.app.errors import ApiError
from backend.app.services.configuration import ConfigurationService


HASH = "B" * 64
SERVICE_FACILITY_OPTIONS = [
    "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
    "SERVICE_FACILITY_ALWAYS_ADDRESS_NO",
    "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES",
    "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO",
    "SERVICE_FACILITY_NEVER",
]


class ResultCursor:
    def __init__(self, columns, rows):
        self.description = [(column,) for column in columns]
        self._rows = rows
        self.closed = False

    def fetchall(self):
        return self._rows

    def close(self):
        self.closed = True


class OutVar:
    def __init__(self, value):
        self._value = value

    def getvalue(self):
        return self._value


class ProcedureCursor:
    def __init__(self, summary, changes, execute_error=None):
        self._outputs = iter([OutVar(summary), OutVar(changes)])
        self.execute_error = execute_error
        self.binds = None
        self.execute_count = 0
        self.closed = False

    def var(self, _type):
        return next(self._outputs)

    def execute(self, _statement, **binds):
        self.execute_count += 1
        self.binds = binds
        if self.execute_error is not None:
            raise self.execute_error

    def close(self):
        self.closed = True


class Connection:
    def __init__(self, cursor):
        self._cursor = cursor
        self.commits = 0
        self.rollbacks = 0
        self.closed = False

    def cursor(self):
        return self._cursor

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1

    def close(self):
        self.closed = True


def make_connection(
    status="PREVIEW",
    option_code="PROVIDER_TAXONOMY_ON",
    display_label="Provider Taxonomy ON",
    change_rows=None,
    execute_error=None,
):
    summary = ResultCursor(
        [
            "STATUS",
            "OPTION_CODE",
            "DISPLAY_LABEL",
            "PFC_GUID",
            "STATE_HASH",
            "CHANGE_COUNT",
        ],
        [
            (
                status,
                option_code,
                display_label,
                "30000000-0000-0000-0000-0000000000A1",
                HASH,
                len(change_rows or []),
            )
        ],
    )
    changes = ResultCursor(
        [
            "OPERATION_ORDER",
            "OPERATION_CODE",
            "TARGET_ELECTRONIC_REC_GUID",
            "FIELD_NUMBER",
        ],
        change_rows or [],
    )
    cursor = ProcedureCursor(summary, changes, execute_error=execute_error)
    return Connection(cursor)


def request_kwargs(option_code="PROVIDER_TAXONOMY_ON"):
    return {
        "payor_guid": "10000000-0000-0000-0000-0000000000A1",
        "plan_guid": None,
        "option_code": option_code,
        "audit_user": "90000000-0000-0000-0000-000000000003",
    }


def test_provider_taxonomy_and_service_facility_are_publicly_advertised():
    fields = ConfigurationService().list_options()["fields"]

    assert [field["field_number"] for field in fields] == ["81", "77"]
    assert fields[0]["field_label"] == "Provider Taxonomy"
    assert [option["option_code"] for option in fields[0]["options"]] == [
        "PROVIDER_TAXONOMY_ON",
        "PROVIDER_TAXONOMY_OFF",
    ]
    assert fields[1]["field_label"] == "Service Facility"
    assert [option["option_code"] for option in fields[1]["options"]] == (
        SERVICE_FACILITY_OPTIONS
    )


def test_preview_rolls_back_and_never_commits():
    connection = make_connection()
    service = ConfigurationService(lambda: connection)

    result = service.preview(**request_kwargs())

    assert result["status"] == "PREVIEW"
    assert connection.commits == 0
    assert connection.rollbacks == 1
    assert connection.closed
    assert connection._cursor.binds["operation_mode"] == "PREVIEW"
    assert connection._cursor.binds["expected_state_hash"] is None


@pytest.mark.parametrize("option_code", SERVICE_FACILITY_OPTIONS)
def test_service_facility_preview_is_one_unchanged_oracle_call(option_code):
    connection = make_connection(
        option_code=option_code,
        display_label="Synthetic Service Facility choice",
    )
    service = ConfigurationService(lambda: connection)

    result = service.preview(**request_kwargs(option_code))

    assert result["option_code"] == option_code
    assert result["field_number"] == "77"
    assert result["state_hash"] == HASH
    assert connection._cursor.execute_count == 1
    assert connection._cursor.binds["option_code"] == option_code
    assert connection._cursor.binds["operation_mode"] == "PREVIEW"
    assert connection._cursor.binds["expected_state_hash"] is None
    assert connection.commits == 0
    assert connection.rollbacks == 1


def test_service_facility_preview_preserves_multi_target_changes():
    change_rows = [
        (1, "INSERT_HER", "31000000-0000-0000-0000-000000000001", None),
        (2, "INSERT_HER", "31000000-0000-0000-0000-000000000002", None),
        (3, "INSERT_HER", "31000000-0000-0000-0000-000000000003", None),
    ]
    connection = make_connection(
        option_code="SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
        display_label="Always report service facility; report address",
        change_rows=change_rows,
    )
    service = ConfigurationService(lambda: connection)

    result = service.preview(
        **request_kwargs("SERVICE_FACILITY_ALWAYS_ADDRESS_YES")
    )

    assert result["change_count"] == 3
    assert [change["target_identifier"] for change in result["debug_changes"]] == [
        row[2] for row in change_rows
    ]


def test_apply_commits_only_after_successful_result():
    connection = make_connection(status="APPLIED")
    service = ConfigurationService(lambda: connection)

    result = service.apply(expected_state_hash=HASH, **request_kwargs())

    assert result["status"] == "APPLIED"
    assert connection.commits == 1
    assert connection.rollbacks == 0
    assert connection.closed
    assert connection._cursor.binds["operation_mode"] == "APPLY"
    assert connection._cursor.binds["expected_state_hash"] == HASH


def test_service_facility_apply_is_one_call_and_forwards_preview_hash():
    option_code = "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO"
    connection = make_connection(
        status="APPLIED",
        option_code=option_code,
        display_label=(
            "Report service facility when care location is not HOME; "
            "do not report address"
        ),
    )
    service = ConfigurationService(lambda: connection)

    result = service.apply(
        expected_state_hash=HASH,
        **request_kwargs(option_code),
    )

    assert result["option_code"] == option_code
    assert result["field_number"] == "77"
    assert connection._cursor.execute_count == 1
    assert connection._cursor.binds["option_code"] == option_code
    assert connection._cursor.binds["expected_state_hash"] == HASH
    assert connection.commits == 1
    assert connection.rollbacks == 0


def test_stale_apply_rolls_back_and_maps_error():
    details = SimpleNamespace(code=20036, message="ORA-20036: stale preview")
    option_code = "SERVICE_FACILITY_ALWAYS_ADDRESS_YES"
    connection = make_connection(
        option_code=option_code,
        display_label="Always report service facility; report address",
        execute_error=oracledb.DatabaseError(details),
    )
    service = ConfigurationService(lambda: connection)

    with pytest.raises(ApiError) as caught:
        service.apply(expected_state_hash=HASH, **request_kwargs(option_code))

    assert caught.value.status_code == 409
    assert caught.value.category == "stale_preview"
    assert connection.commits == 0
    assert connection.rollbacks == 1
    assert connection.closed
    assert connection._cursor.execute_count == 1
