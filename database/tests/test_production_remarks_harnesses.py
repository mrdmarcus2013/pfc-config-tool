from __future__ import annotations

import os
import re
from pathlib import Path

import oracledb
import pytest

from database.run_poc import connect


ROOT = Path(__file__).resolve().parents[2]
READONLY_PATH = ROOT / "database" / "production_tests" / "10_remarks_readonly.sql"
PREVIEW_PATH = ROOT / "database" / "production_tests" / "11_remarks_preview.sql"
APPLY_PATH = ROOT / "database" / "production_tests" / "12_remarks_apply_rollback.sql"
PAYOR = "10000000-0000-0000-0000-00000000D001"
AUDIT_USER = "DANIEL"

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_PRODUCTION_HARNESS_INTEGRATION") != "1",
    reason="set RUN_ORACLE_PRODUCTION_HARNESS_INTEGRATION=1 for local Oracle harness tests",
)


class HarnessFailure(Exception):
    pass


def read_output(cursor: oracledb.Cursor) -> list[str]:
    lines: list[str] = []
    values = cursor.arrayvar(str, 100, 32767)
    count = cursor.var(int)
    while True:
        count.setvalue(0, 100)
        cursor.callproc("dbms_output.get_lines", (values, count))
        received = count.getvalue()
        lines.extend(line for line in values.getvalue()[:received] if line is not None)
        if received < 100:
            return lines


def execute_harness(connection: oracledb.Connection, text: str) -> list[str]:
    start = text.index("DECLARE")
    end_match = re.search(r"\n/\s*$", text)
    assert end_match is not None
    block = text[start:end_match.start()]
    with connection.cursor() as cursor:
        cursor.execute("BEGIN DBMS_OUTPUT.ENABLE(NULL); END;")
        try:
            cursor.execute(block)
        except Exception as exc:
            output = read_output(cursor)
            raise HarnessFailure("\n".join(output + [str(exc)])) from exc
        return read_output(cursor)


def configured_script(
    path: Path,
    *,
    lob: str,
    mode: str,
    custom_remark: str | None,
    expected_hash: str | None = None,
) -> str:
    text = path.read_text(encoding="utf-8")
    custom_literal = "NULL" if custom_remark is None else "'" + custom_remark.replace("'", "''") + "'"
    replacements = [
        ("'PUT_PAYOR_GUID_HERE'", f"'{PAYOR}'"),
        ("c_line_of_business CONSTANT VARCHAR2(20) := 'HOME_HEALTH'",
         f"c_line_of_business CONSTANT VARCHAR2(20) := '{lob}'"),
        ("c_mode CONSTANT VARCHAR2(10) := 'DEFAULT'",
         f"c_mode CONSTANT VARCHAR2(10) := '{mode}'"),
        ("c_custom_remark CONSTANT VARCHAR2(128) := NULL",
         f"c_custom_remark CONSTANT VARCHAR2(128) := {custom_literal}"),
        ("'PUT_AUDIT_USER_HERE'", f"'{AUDIT_USER}'"),
    ]
    if expected_hash is not None:
        replacements.append((
            "'PUT_EXPECTED_PREVIEW_STATE_HASH_HERE'",
            f"'{expected_hash}'",
        ))
    for old, new in replacements:
        assert old in text
        text = text.replace(old, new, 1)
    return text


def output_value(output: list[str], label: str) -> str:
    prefix = label + ": "
    return next(line[len(prefix):] for line in output if line.startswith(prefix))


def execute_readonly(connection: oracledb.Connection) -> tuple[list[str], list[tuple]]:
    text = READONLY_PATH.read_text(encoding="utf-8").replace(
        "'PUT_PAYOR_GUID_HERE'", f"'{PAYOR}'", 1
    )
    statement = text[text.index("WITH\n"):].rstrip().removesuffix(";")
    with connection.cursor() as cursor:
        cursor.execute(statement)
        columns = [column[0].lower() for column in cursor.description]
        return columns, cursor.fetchall()


@pytest.fixture
def oracle_connection():
    connection = connect()
    host = (os.getenv("ORACLE_HOST") or "").lower()
    service = os.getenv("ORACLE_SERVICE_NAME") or os.getenv("ORACLE_SERVICE")
    if host not in {"localhost", "127.0.0.1", "::1"} or service != "FREEPDB1":
        connection.close()
        pytest.fail("Remarks harness integration is restricted to local loopback FREEPDB1.")
    try:
        yield connection
    finally:
        connection.rollback()
        connection.close()


@pytest.mark.parametrize("lob", ["HOME_HEALTH", "HOSPICE"])
@pytest.mark.parametrize(
    ("mode", "custom_remark", "expected_action"),
    [
        ("DEFAULT", None, "NO_CHANGE"),
        ("CUSTOM", "Call provider before processing", "REBUILD_OVERRIDE"),
    ],
)
def test_preview_runs_for_both_lobs_and_modes(
    oracle_connection, lob, mode, custom_remark, expected_action,
):
    output = execute_harness(
        oracle_connection,
        configured_script(
            PREVIEW_PATH, lob=lob, mode=mode, custom_remark=custom_remark,
        ),
    )
    assert output_value(output, "TARGET_ACTION") == expected_action
    assert output_value(output, "SOURCE_HEF_COUNT") == "4"
    assert len(output_value(output, "STATE_HASH")) == 64
    assert output[-1] == "READ-ONLY PREVIEW: NO DML PERFORMED"


def test_readonly_script_runs_standalone_and_reports_zero_override_as_default(
    oracle_connection,
):
    columns, rows = execute_readonly(oracle_connection)
    summary = dict(zip(columns, rows[0]))
    assert summary["output_section"] == "SUMMARY"
    assert summary["status"] == "RESOLVED"
    assert summary["current_mode"] == "DEFAULT"
    assert summary["record_type_code"] == "D23001900NTE182"
    assert summary["source_hef_count"] == 4
    assert summary["existing_payor_her_count"] == 0


def test_remarks_default_blocks_unsafe_source_and_custom_preserves_return_1_value(
    oracle_connection,
):
    with oracle_connection.cursor() as cursor:
        cursor.execute(
            """
            UPDATE hcfa_electronic_records
            SET mandatory_ind = 'Y'
            WHERE electronic_rec_guid =
                '33000000-0000-0000-0000-000000000001'
            """
        )
    columns, rows = execute_readonly(oracle_connection)
    summary = dict(zip(columns, rows[0]))
    assert summary["status"] == "BLOCKED_SOURCE_INVALID_MANDATORY"
    assert summary["source_safety_status"] == "INVALID_MANDATORY_COMBINATION"

    with pytest.raises(HarnessFailure, match="STATUS: BLOCKED"):
        execute_harness(
            oracle_connection,
            configured_script(
                PREVIEW_PATH, lob="HOME_HEALTH", mode="DEFAULT",
                custom_remark=None,
            ),
        )
    custom = execute_harness(
        oracle_connection,
        configured_script(
            PREVIEW_PATH, lob="HOME_HEALTH", mode="CUSTOM",
            custom_remark="Safe explicit repair",
        ),
    )
    assert output_value(custom, "SOURCE_HER_MANDATORY_IND") == "Y"
    assert output_value(custom, "DESIRED_HER_STO_PROC_NAME") == "RETURN_1"
    assert output_value(custom, "DESIRED_HER_MANDATORY_IND") == "Y"


@pytest.mark.parametrize("lob", ["HOME_HEALTH", "HOSPICE"])
def test_apply_accepts_preview_hash_and_restores_exact_state(oracle_connection, lob):
    selection = {
        "lob": lob,
        "mode": "CUSTOM",
        "custom_remark": "Authorization required before billing",
    }
    preview = execute_harness(
        oracle_connection, configured_script(PREVIEW_PATH, **selection)
    )
    output = execute_harness(
        oracle_connection,
        configured_script(
            APPLY_PATH,
            expected_hash=output_value(preview, "STATE_HASH"),
            **selection,
        ),
    )
    assert "HASH MATCH: YES" in output
    assert "TEMPORARY_CANONICAL_STATE: VERIFIED" in output
    assert "ORIGINAL_STATE_RESTORED: VERIFIED" in output
    assert output[-1] == "ROLLBACK-ONLY APPLY: NO CHANGES RETAINED"


def test_apply_rejects_changed_custom_text_as_stale(oracle_connection):
    preview = execute_harness(
        oracle_connection,
        configured_script(
            PREVIEW_PATH,
            lob="HOME_HEALTH",
            mode="CUSTOM",
            custom_remark="First remark",
        ),
    )
    with pytest.raises(HarnessFailure, match="ORA-20605"):
        execute_harness(
            oracle_connection,
            configured_script(
                APPLY_PATH,
                lob="HOME_HEALTH",
                mode="CUSTOM",
                custom_remark="Changed remark",
                expected_hash=output_value(preview, "STATE_HASH"),
            ),
        )
