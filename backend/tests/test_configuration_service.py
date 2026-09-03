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


class CurrentProcedureCursor:
    def __init__(self, result, execute_error=None):
        self._output = OutVar(result)
        self.execute_error = execute_error
        self.binds = None
        self.execute_count = 0
        self.closed = False

    def var(self, _type):
        return self._output

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


def make_current_connection(
    *,
    field_number="81",
    capability="provider-taxonomy",
    option_code="PROVIDER_TAXONOMY_ON",
    mode=None,
    report_address=None,
    enabled="Y",
    canonical="Y",
    execute_error=None,
):
    result = ResultCursor(
        [
            "STATUS", "FIELD_NUMBER", "CAPABILITY", "EFFECTIVE_OPTION_CODE",
            "MODE", "REPORT_ADDRESS", "ENABLED", "PFC_GUID", "IS_CANONICAL",
        ],
        [[
            "RESOLVED", field_number, capability, option_code, mode,
            report_address, enabled,
            "30000000-0000-0000-0000-0000000000A1", canonical,
        ]],
    )
    return Connection(CurrentProcedureCursor(result, execute_error=execute_error))


def make_value_codes_current_connection():
    columns = ["CONFIGURATION_STATUS", "LINE_OF_BUSINESS", "IS_DEFAULT",
        "CBSA", "FIPS", "CARE_LOCATION_VALUE_CODE",
        "PATIENT_ENTERED_VALUE_CODE", "COVERED_DAYS_VALUE_CODE",
        "CANONICAL_STATUS", "DISPLAY_SUMMARY", "PFC_GUID",
        "BILLING_FORM_CODE", "SOURCE_ELECTRONIC_REC_GUID",
        "EXISTING_PAYOR_HER_COUNT", "EXISTING_PAYOR_HEF_COUNT", "STATE_HASH"]
    row = ["RESOLVED", "HOME_HEALTH", "Y", "N", "N", "N", "N", "N",
        "INHERITED", "Default", "synthetic-pfc", "837I_5010",
        "synthetic-source", 0, 0, HASH]
    return Connection(CurrentProcedureCursor(ResultCursor(columns, [row])))


def test_public_capabilities_include_structured_fields_without_private_ids():
    fields = ConfigurationService().list_options()["fields"]

    assert [field["field_number"] for field in fields] == ["81", "77", "39-41", "80"]
    assert fields[0]["field_label"] == "Provider Taxonomy"
    assert [option["option_code"] for option in fields[0]["options"]] == [
        "PROVIDER_TAXONOMY_ON",
        "PROVIDER_TAXONOMY_OFF",
    ]
    assert fields[1]["field_label"] == "Service Facility"
    assert [option["option_code"] for option in fields[1]["options"]] == (
        SERVICE_FACILITY_OPTIONS
    )
    assert fields[2] == {
        "field_number": "39-41", "field_label": "Value Codes", "options": []
    }
    assert fields[3] == {
        "field_number": "80", "field_label": "Remarks", "options": []
    }


def make_remarks_current_connection(mode="DEFAULT", custom_remark=None,
                                    status="RESOLVED"):
    columns = ["CONFIGURATION_STATUS", "LINE_OF_BUSINESS", "REMARKS_MODE",
        "CUSTOM_REMARK", "CANONICAL_STATUS", "DISPLAY_SUMMARY", "PFC_GUID",
        "BILLING_FORM_CODE", "SOURCE_ELECTRONIC_REC_GUID", "TARGET_ACTION",
        "EXISTING_PAYOR_HER_COUNT", "EXISTING_PAYOR_HEF_COUNT",
        "SOURCE_HEF_COUNT", "STATE_HASH"]
    row = [status, "HOME_HEALTH", mode, custom_remark,
        "INHERITED" if mode == "DEFAULT" else "CANONICAL_OVERRIDE",
        "Default" if mode == "DEFAULT" else "Custom remark",
        "synthetic-pfc", "837I_5010", "synthetic-source", "NO_CHANGE",
        0 if mode == "DEFAULT" else 1, 0 if mode == "DEFAULT" else 4, 4, HASH]
    return Connection(CurrentProcedureCursor(ResultCursor(columns, [row])))


def test_remarks_current_maps_default_and_exact_custom_text():
    default_connection = make_remarks_current_connection()
    default = ConfigurationService(lambda: default_connection).remarks_current(
        payor_guid=request_kwargs()["payor_guid"], plan_guid=None)
    assert default["mode"] == "DEFAULT"
    assert default["custom_remark"] is None
    assert default_connection.rollbacks == 1

    text = "Contact agency for additional documentation"
    custom_connection = make_remarks_current_connection("CUSTOM", text)
    custom = ConfigurationService(lambda: custom_connection).remarks_current(
        payor_guid=request_kwargs()["payor_guid"], plan_guid=None)
    assert custom["mode"] == "CUSTOM"
    assert custom["custom_remark"] == text
    assert custom["debug"]["source_hef_count"] == 4


def test_remarks_current_blocks_unsupported_state():
    connection = make_remarks_current_connection(status="UNRECOGNIZED")
    with pytest.raises(ApiError) as caught:
        ConfigurationService(lambda: connection).remarks_current(
            payor_guid=request_kwargs()["payor_guid"], plan_guid=None)
    assert caught.value.category == "current_state_unsupported"
    assert connection.rollbacks == 1


def test_remarks_preview_and_apply_bind_structured_text_and_hash():
    text = "Authorization required before billing"
    preview_connection = make_connection(display_label="Custom remark")
    preview = ConfigurationService(lambda: preview_connection).remarks_preview(
        payor_guid=request_kwargs()["payor_guid"], plan_guid=None,
        mode="CUSTOM", custom_remark=text,
        audit_user=request_kwargs()["audit_user"])
    assert preview["custom_remark"] == text
    assert preview_connection._cursor.binds["remarks_mode"] == "CUSTOM"
    assert preview_connection._cursor.binds["custom_remark"] == text
    assert "option_code" not in preview_connection._cursor.binds
    assert preview_connection.rollbacks == 1

    apply_connection = make_connection(status="APPLIED", display_label="Custom remark")
    applied = ConfigurationService(lambda: apply_connection).remarks_apply(
        payor_guid=request_kwargs()["payor_guid"], plan_guid=None,
        mode="CUSTOM", custom_remark=text,
        audit_user=request_kwargs()["audit_user"], expected_state_hash=HASH)
    assert applied["status"] == "APPLIED"
    assert apply_connection._cursor.binds["expected_state_hash"] == HASH
    assert apply_connection.commits == 1


@pytest.mark.parametrize(
    ("operation", "oracle_code", "category"),
    [
        ("current", 20070, "line_of_business_required"),
        ("preview", 20070, "line_of_business_required"),
        ("apply", 20036, "stale_preview"),
    ],
)
def test_remarks_failures_are_safe_and_always_roll_back(
    operation, oracle_code, category,
):
    details = SimpleNamespace(
        code=oracle_code, message="ORA raw Remarks implementation detail"
    )
    if operation == "current":
        base = make_remarks_current_connection()
        connection = Connection(CurrentProcedureCursor(
            base._cursor._output.getvalue(), oracledb.DatabaseError(details)
        ))
        call = lambda service: service.remarks_current(
            payor_guid=request_kwargs()["payor_guid"], plan_guid=None
        )
    else:
        connection = make_connection(execute_error=oracledb.DatabaseError(details))
        call = lambda service: getattr(service, f"remarks_{operation}")(
            payor_guid=request_kwargs()["payor_guid"],
            plan_guid=None,
            mode="CUSTOM",
            custom_remark="Synthetic remark",
            audit_user=request_kwargs()["audit_user"],
            **({"expected_state_hash": HASH} if operation == "apply" else {}),
        )
    with pytest.raises(ApiError) as caught:
        call(ConfigurationService(lambda: connection))
    assert caught.value.category == category
    assert "oracle" not in caught.value.message.lower()
    assert connection.commits == 0
    assert connection.rollbacks == 1


def test_value_codes_current_maps_structured_default_and_rolls_back():
    connection = make_value_codes_current_connection()
    result = ConfigurationService(lambda: connection).value_codes_current(
        payor_guid=request_kwargs()["payor_guid"], plan_guid=None)
    assert result["is_default"] is True
    assert result["display_summary"] == "Default"
    assert not any(result["selections"].values())
    assert connection.rollbacks == 1
    assert connection.commits == 0


def test_value_codes_preview_and_apply_bind_flags_without_public_recipe_id():
    selections = {"cbsa": True, "fips": False,
        "care_location_value_code": False,
        "patient_entered_value_code": False,
        "covered_days_value_code": False}
    preview_connection = make_connection(display_label="CBSA")
    preview = ConfigurationService(lambda: preview_connection).value_codes_preview(
        payor_guid=request_kwargs()["payor_guid"], plan_guid=None,
        selections=selections, audit_user=request_kwargs()["audit_user"])
    assert preview["display_summary"] == "CBSA"
    assert preview_connection.rollbacks == 1
    assert preview_connection._cursor.binds["cbsa"] == "Y"
    assert "option_code" not in preview_connection._cursor.binds

    apply_connection = make_connection(status="APPLIED", display_label="CBSA")
    applied = ConfigurationService(lambda: apply_connection).value_codes_apply(
        payor_guid=request_kwargs()["payor_guid"], plan_guid=None,
        selections=selections, audit_user=request_kwargs()["audit_user"],
        expected_state_hash=HASH)
    assert applied["status"] == "APPLIED"
    assert apply_connection.commits == 1
    assert apply_connection._cursor.binds["expected_state_hash"] == HASH


def test_current_provider_is_one_read_only_oracle_call():
    connection = make_current_connection()
    service = ConfigurationService(lambda: connection)

    result = service.current(
        payor_guid=request_kwargs()["payor_guid"],
        plan_guid=None,
        field_number="81",
    )

    assert result == {
        "status": "RESOLVED",
        "field_number": "81",
        "capability": "provider-taxonomy",
        "effective_option_code": "PROVIDER_TAXONOMY_ON",
        "display": {"mode": None, "report_address": None, "enabled": True},
        "pfc_guid": "30000000-0000-0000-0000-0000000000A1",
        "canonical": True,
    }
    assert connection._cursor.execute_count == 1
    assert connection._cursor.binds == {
        "payor_guid": request_kwargs()["payor_guid"],
        "plan_guid": None,
        "field_number": "81",
        "result_cursor": connection._cursor._output,
    }
    assert connection.commits == 0
    assert connection.rollbacks == 1
    assert connection.closed


def test_current_service_facility_maps_display_without_commit():
    connection = make_current_connection(
        field_number="77",
        capability="service-facility",
        option_code="SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO",
        mode="CONDITIONAL",
        report_address="N",
        enabled=None,
        canonical=None,
    )
    service = ConfigurationService(lambda: connection)

    result = service.current(
        payor_guid=request_kwargs()["payor_guid"],
        plan_guid=None,
        field_number="77",
    )

    assert result["effective_option_code"] == "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO"
    assert result["display"] == {
        "mode": "CONDITIONAL",
        "report_address": "N",
        "enabled": None,
    }
    assert result["canonical"] is None
    assert connection.commits == 0
    assert connection.rollbacks == 1


def test_current_invalid_oracle_result_rolls_back_and_fails_safely():
    connection = make_current_connection(option_code="PROVIDER_TAXONOMY_OFF", enabled="INVALID")
    service = ConfigurationService(lambda: connection)

    with pytest.raises(ApiError) as caught:
        service.current(
            payor_guid=request_kwargs()["payor_guid"],
            plan_guid=None,
            field_number="81",
        )

    assert caught.value.status_code == 500
    assert caught.value.category == "application_failure"
    assert connection.commits == 0
    assert connection.rollbacks == 1


def test_current_unsupported_oracle_state_maps_safe_error():
    details = SimpleNamespace(code=20041, message="ORA-20041 raw mixed state")
    connection = make_current_connection(
        execute_error=oracledb.DatabaseError(details),
    )
    service = ConfigurationService(lambda: connection)

    with pytest.raises(ApiError) as caught:
        service.current(
            payor_guid=request_kwargs()["payor_guid"],
            plan_guid=None,
            field_number="81",
        )

    assert caught.value.status_code == 409
    assert caught.value.category == "current_state_unsupported"
    assert "mixed" not in caught.value.message.lower()
    assert connection.commits == 0
    assert connection.rollbacks == 1


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


def make_lob_change_connection(status="CHANGES_REQUIRED", execute_error=None):
    summary = ResultCursor(
        [
            "STATUS", "CHANGES_REQUIRED", "CURRENT_LINE_OF_BUSINESS",
            "REQUESTED_LINE_OF_BUSINESS", "MANAGED_TARGET_COUNT",
            "AFFECTED_MANAGED_TARGET_COUNT", "MANAGED_HER_COUNT",
            "MANAGED_HEF_COUNT", "PREVIEW_STATE_HASH",
        ],
        [[status, "N" if status == "NO_CHANGE" else "Y", "HOME_HEALTH",
          "HOSPICE", 4, 2, 3, 9, HASH]],
    )
    targets = ResultCursor(
        ["TARGET_ORDER", "BILLING_FORM_CODE", "RECORD_TYPE_CODE", "HER_COUNT", "HEF_COUNT"],
        [[1, "837I_5010", "B2000A0030PRV080", 1, 4]],
    )
    return Connection(ProcedureCursor(summary, targets, execute_error=execute_error))


def test_lob_current_is_payor_only_read_and_rolls_back():
    result = ResultCursor(["STATUS", "LINE_OF_BUSINESS"], [["UNDEFINED", None]])
    connection = Connection(CurrentProcedureCursor(result))
    service = ConfigurationService(lambda: connection)

    response = service.line_of_business_current(payor_guid=request_kwargs()["payor_guid"])

    assert response == {"status": "UNDEFINED", "line_of_business": None}
    assert connection._cursor.binds == {
        "payor_guid": request_kwargs()["payor_guid"],
        "result_cursor": connection._cursor._output,
    }
    assert connection.commits == 0
    assert connection.rollbacks == 1


def test_lob_initial_save_commits_only_after_success():
    result = ResultCursor(["STATUS", "LINE_OF_BUSINESS"], [["SAVED", "HOME_HEALTH"]])
    connection = Connection(CurrentProcedureCursor(result))
    service = ConfigurationService(lambda: connection)

    response = service.line_of_business_save(
        payor_guid=request_kwargs()["payor_guid"],
        line_of_business="HOME_HEALTH",
        audit_user=request_kwargs()["audit_user"],
    )

    assert response["status"] == "SAVED"
    assert connection.commits == 1
    assert connection.rollbacks == 0


def test_lob_change_preview_rolls_back_and_retains_technical_counts():
    connection = make_lob_change_connection()
    service = ConfigurationService(lambda: connection)

    response = service.line_of_business_preview_change(
        payor_guid=request_kwargs()["payor_guid"],
        requested_line_of_business="HOSPICE",
    )

    assert response["status"] == "CHANGES_REQUIRED"
    assert response["preview_state_hash"] == HASH
    assert response["managed_target_count"] == 4
    assert response["debug_targets"][0]["record_type_code"] == "B2000A0030PRV080"
    assert connection.commits == 0
    assert connection.rollbacks == 1


def test_lob_change_apply_forwards_exact_hash_and_commits():
    connection = make_lob_change_connection(status="APPLIED")
    service = ConfigurationService(lambda: connection)

    response = service.line_of_business_apply_change(
        payor_guid=request_kwargs()["payor_guid"],
        requested_line_of_business="HOSPICE",
        expected_state_hash=HASH,
        audit_user=request_kwargs()["audit_user"],
    )

    assert response["status"] == "APPLIED"
    assert connection._cursor.binds["expected_state_hash"] == HASH
    assert connection.commits == 1
    assert connection.rollbacks == 0


@pytest.mark.parametrize(
    ("operation", "oracle_code", "category"),
    [
        ("save", 20052, "line_of_business_already_saved"),
        ("apply", 20055, "stale_preview"),
    ],
)
def test_lob_write_failures_roll_back_and_map_safely(operation, oracle_code, category):
    details = SimpleNamespace(code=oracle_code, message="ORA raw implementation detail")
    if operation == "save":
        result = ResultCursor(["STATUS", "LINE_OF_BUSINESS"], [])
        connection = Connection(CurrentProcedureCursor(result, oracledb.DatabaseError(details)))
        call = lambda service: service.line_of_business_save(
            payor_guid=request_kwargs()["payor_guid"], line_of_business="HOME_HEALTH",
            audit_user=request_kwargs()["audit_user"])
    else:
        connection = make_lob_change_connection(execute_error=oracledb.DatabaseError(details))
        call = lambda service: service.line_of_business_apply_change(
            payor_guid=request_kwargs()["payor_guid"], requested_line_of_business="HOSPICE",
            expected_state_hash=HASH, audit_user=request_kwargs()["audit_user"])
    with pytest.raises(ApiError) as caught:
        call(ConfigurationService(lambda: connection))
    assert caught.value.category == category
    assert "oracle" not in caught.value.message.lower()
    assert connection.commits == 0
    assert connection.rollbacks == 1


@pytest.mark.parametrize("operation", ["current", "preview", "apply"])
def test_public_field_operations_require_saved_lob(operation):
    details = SimpleNamespace(code=20053, message="raw LOB gate detail")
    if operation == "current":
        connection = make_current_connection(execute_error=oracledb.DatabaseError(details))
        call = lambda service: service.current(
            payor_guid=request_kwargs()["payor_guid"], plan_guid=None, field_number="81")
    else:
        connection = make_connection(execute_error=oracledb.DatabaseError(details))
        call = lambda service: getattr(service, operation)(
            **request_kwargs(), **({"expected_state_hash": HASH} if operation == "apply" else {}))
    with pytest.raises(ApiError) as caught:
        call(ConfigurationService(lambda: connection))
    assert caught.value.status_code == 409
    assert caught.value.category == "line_of_business_required"
    assert connection.commits == 0
    assert connection.rollbacks == 1
