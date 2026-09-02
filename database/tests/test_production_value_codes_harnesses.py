from __future__ import annotations

import os
import re
from pathlib import Path

import oracledb
import pytest

from database.run_poc import ACTION_SCRIPTS, connect, execute_script


ROOT = Path(__file__).resolve().parents[2]
PREVIEW_PATH = ROOT / "database" / "production_tests" / "08_value_codes_preview.sql"
APPLY_PATH = ROOT / "database" / "production_tests" / "09_value_codes_apply_rollback.sql"
PAYOR = "10000000-0000-0000-0000-00000000D002"
AUDIT_USER = "DANIEL"
TARGET = "D23002310HI286"

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_PRODUCTION_HARNESS_INTEGRATION") != "1",
    reason="set RUN_ORACLE_PRODUCTION_HARNESS_INTEGRATION=1 for local Oracle harness tests",
)


class HarnessFailure(Exception):
    def __init__(self, cause: Exception, output: list[str]):
        super().__init__(str(cause))
        self.cause = cause
        self.output = output


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
            raise HarnessFailure(exc, output) from exc
        return read_output(cursor)


def configured_script(
    path: Path,
    *,
    lob: str,
    cbsa: str = "N",
    fips: str = "N",
    care: str = "N",
    patient: str = "N",
    days: str = "N",
    expected_hash: str | None = None,
) -> str:
    text = path.read_text(encoding="utf-8")
    replacements = [
        ("'PUT_PAYOR_GUID_HERE'", f"'{PAYOR}'"),
        ("c_line_of_business CONSTANT VARCHAR2(20) := 'HOME_HEALTH'",
         f"c_line_of_business CONSTANT VARCHAR2(20) := '{lob}'"),
        ("c_cbsa CONSTANT VARCHAR2(1) := 'N'",
         f"c_cbsa CONSTANT VARCHAR2(1) := '{cbsa}'"),
        ("c_fips CONSTANT VARCHAR2(1) := 'N'",
         f"c_fips CONSTANT VARCHAR2(1) := '{fips}'"),
        ("c_care_location_value_code CONSTANT VARCHAR2(1) := 'N'",
         f"c_care_location_value_code CONSTANT VARCHAR2(1) := '{care}'"),
        ("c_patient_entered_value_code CONSTANT VARCHAR2(1) := 'N'",
         f"c_patient_entered_value_code CONSTANT VARCHAR2(1) := '{patient}'"),
        ("c_covered_days_value_code CONSTANT VARCHAR2(1) := 'N'",
         f"c_covered_days_value_code CONSTANT VARCHAR2(1) := '{days}'"),
        ("'PUT_AUDIT_USER_HERE'", f"'{AUDIT_USER}'"),
    ]
    if expected_hash is not None:
        replacements.append((
            "'PUT_64_CHARACTER_PREVIEW_STATE_HASH_HERE'",
            f"'{expected_hash}'",
        ))
    for old, new in replacements:
        assert old in text
        text = text.replace(old, new, 1)
    return text


def output_value(output: list[str], label: str) -> str:
    prefix = label + ": "
    return next(line[len(prefix):] for line in output if line.startswith(prefix))


@pytest.fixture
def oracle_connection():
    connection = connect()
    host = (os.getenv("ORACLE_HOST") or "").lower()
    service = os.getenv("ORACLE_SERVICE_NAME") or os.getenv("ORACLE_SERVICE")
    if host not in {"localhost", "127.0.0.1", "::1"} or service != "FREEPDB1":
        connection.close()
        pytest.fail(
            "Standalone production-harness integration tests are restricted "
            "to local loopback Oracle FREEPDB1."
        )
    try:
        yield connection
    finally:
        connection.rollback()
        connection.close()


@pytest.mark.parametrize(("lob", "flags", "label"), [
    ("HOME_HEALTH", {}, "Default"),
    ("HOME_HEALTH", {"cbsa": "Y"}, "CBSA"),
    ("HOME_HEALTH", {"cbsa": "Y", "fips": "Y"}, "CBSA and FIPS"),
    ("HOSPICE", {}, "Default"),
    ("HOSPICE", {"care": "Y"}, "Care-location value code 61/G8"),
    ("HOSPICE", {"care": "Y", "days": "Y"},
     "Care-location value code 61/G8 and VC80/days"),
    ("HOSPICE", {"patient": "Y"}, "Patient-entered value code and amount"),
    ("HOSPICE", {"patient": "Y", "days": "Y"},
     "Patient-entered value code and VC80/days"),
    ("HOSPICE", {"days": "Y"}, "Value code 80 with days covered"),
])
def test_preview_supports_every_valid_value_codes_state(
    oracle_connection, lob, flags, label,
):
    output = execute_harness(
        oracle_connection,
        configured_script(PREVIEW_PATH, lob=lob, **flags),
    )
    assert output_value(output, "SELECTION") == label
    assert output_value(output, "SOURCE_HEF_COUNT") == "5"
    assert output_value(output, "STATE_HASH")
    assert output[-2] == "READ-ONLY PREVIEW: NO DML PERFORMED"


@pytest.mark.parametrize(("lob", "flags"), [
    ("HOME_HEALTH", {"fips": "Y"}),
    ("HOSPICE", {"care": "Y", "patient": "Y"}),
    ("HOSPICE", {"care": "Y", "patient": "Y", "days": "Y"}),
])
def test_preview_rejects_invalid_combinations(oracle_connection, lob, flags):
    with pytest.raises(HarnessFailure, match="ORA-20501"):
        execute_harness(
            oracle_connection,
            configured_script(PREVIEW_PATH, lob=lob, **flags),
        )


def preview_and_hash(connection, **selection):
    output = execute_harness(
        connection,
        configured_script(PREVIEW_PATH, **selection),
    )
    return output, output_value(output, "STATE_HASH")


def apply_with_hash(connection, state_hash, **selection):
    return execute_harness(
        connection,
        configured_script(APPLY_PATH, expected_hash=state_hash, **selection),
    )


def insert_current_override(connection):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO hcfa_electronic_records (
                electronic_rec_guid, loop_id, contiguity_ind,
                billing_form_code, record_name, record_type_code, record_size,
                mandatory_ind, req_for_claim_ind, payor_type_guid, payor_guid,
                plan_guid, type_of_bill, detail_ind, max_number, invoice_ind,
                form_template_guid, carry_forward_ind, max_carry_forward,
                sto_proc_name, user_form_template_guid, notes, rec_ent_date,
                rec_ent_user, rec_mod_date, rec_mod_user,
                include_record_data_onclaim
            )
            SELECT RAWTOHEX(SYS_GUID()), h.loop_id, h.contiguity_ind,
                h.billing_form_code, 'Synthetic standalone harness override',
                h.record_type_code, h.record_size, h.mandatory_ind,
                h.req_for_claim_ind, p.payor_type_guid, :payor_guid,
                NULL, h.type_of_bill, h.detail_ind, h.max_number,
                h.invoice_ind, h.form_template_guid, NULL,
                h.max_carry_forward, h.sto_proc_name,
                h.user_form_template_guid, h.notes, SYSDATE, :audit_user,
                NULL, NULL, 'Y'
            FROM hcfa_electronic_records h
            CROSS JOIN payors p
            WHERE h.electronic_rec_guid =
                    '32000000-0000-0000-0000-000000000001'
              AND p.payor_guid = :payor_guid
            """,
            payor_guid=PAYOR,
            audit_user=AUDIT_USER,
        )


def test_preview_hash_is_accepted_and_rebuild_is_exactly_restored(oracle_connection):
    _, state_hash = preview_and_hash(oracle_connection, lob="HOME_HEALTH", cbsa="Y")
    output = apply_with_hash(
        oracle_connection, state_hash, lob="HOME_HEALTH", cbsa="Y",
    )
    assert "HASH MATCH: YES" in output
    assert "HI VERIFY PASS: 1 HER / 5 HEFs" in output
    assert "RESTORATION HASH MATCH: YES" in output


def test_default_no_change_and_remove_override_restore(oracle_connection):
    output, state_hash = preview_and_hash(oracle_connection, lob="HOME_HEALTH")
    assert output_value(output, "TARGET_ACTION") == "NO_CHANGE"
    assert "HASH MATCH: YES" in apply_with_hash(
        oracle_connection, state_hash, lob="HOME_HEALTH",
    )

    insert_current_override(oracle_connection)
    output, state_hash = preview_and_hash(oracle_connection, lob="HOME_HEALTH")
    assert output_value(output, "TARGET_ACTION") == "REMOVE_OVERRIDE"
    applied = apply_with_hash(oracle_connection, state_hash, lob="HOME_HEALTH")
    assert "HI VERIFY PASS: 0 HER / 0 HEFs" in applied
    assert "RESTORATION HASH MATCH: YES" in applied


def test_selection_source_and_current_changes_each_reject_stale_hash(oracle_connection):
    preview, state_hash = preview_and_hash(
        oracle_connection, lob="HOME_HEALTH", cbsa="Y",
    )
    assert output_value(preview, "TARGET_ACTION") == "REBUILD_OVERRIDE"
    with pytest.raises(HarnessFailure, match="ORA-20504"):
        apply_with_hash(
            oracle_connection, state_hash,
            lob="HOME_HEALTH", cbsa="Y", fips="Y",
        )

    _, state_hash = preview_and_hash(oracle_connection, lob="HOME_HEALTH", cbsa="Y")
    with oracle_connection.cursor() as cursor:
        cursor.execute(
            """
            UPDATE hcfa_electronic_fields
            SET hard_coded_data = hard_coded_data || '_CHANGED'
            WHERE electronic_rec_guid =
                    '32000000-0000-0000-0000-000000000001'
              AND field_number = '030'
            """
        )
    with pytest.raises(HarnessFailure, match="ORA-20504"):
        apply_with_hash(
            oracle_connection, state_hash, lob="HOME_HEALTH", cbsa="Y",
        )

    _, state_hash = preview_and_hash(oracle_connection, lob="HOME_HEALTH", cbsa="Y")
    insert_current_override(oracle_connection)
    with pytest.raises(HarnessFailure, match="ORA-20504"):
        apply_with_hash(
            oracle_connection, state_hash, lob="HOME_HEALTH", cbsa="Y",
        )


def test_injected_failure_uses_restoration_and_full_rollback(oracle_connection):
    _, state_hash = preview_and_hash(oracle_connection, lob="HOME_HEALTH", cbsa="Y")
    text = configured_script(
        APPLY_PATH, expected_hash=state_hash, lob="HOME_HEALTH", cbsa="Y",
    )
    injection_point = "    delete_all_target_hers;\n    insert_all_target_hers;"
    assert injection_point in text
    text = text.replace(
        injection_point,
        "    delete_all_target_hers;\n"
        "    RAISE_APPLICATION_ERROR(-20988, 'Synthetic injected failure');\n"
        "    insert_all_target_hers;",
        1,
    )
    with pytest.raises(HarnessFailure) as raised:
        execute_harness(oracle_connection, text)
    assert "ORA-20988" in str(raised.value)
    assert "FAILURE PATH RESTORATION VERIFICATION: PASS" in raised.value.output
    assert "FINAL FULL ROLLBACK COMPLETE ON FAILURE." in raised.value.output


def test_harnesses_run_while_tool_objects_are_unavailable(oracle_connection):
    cursor = oracle_connection.cursor()
    renamed_context = False
    try:
        cursor.execute("ALTER TABLE pfc_config_payor_context RENAME TO pfc_ctx_test_hold")
        renamed_context = True
        cursor.execute("DROP PACKAGE pfc_value_codes_api")
        cursor.execute("DROP PACKAGE pfc_value_codes")
        cursor.execute("DROP PROCEDURE pfc_apply_option")
        cursor.execute(
            """
            SELECT COUNT(*) FROM user_objects
            WHERE object_name IN (
                'PFC_CONFIG_PAYOR_CONTEXT', 'PFC_VALUE_CODES',
                'PFC_VALUE_CODES_API', 'PFC_APPLY_OPTION'
            )
            """
        )
        assert cursor.fetchone()[0] == 0

        _, state_hash = preview_and_hash(
            oracle_connection, lob="HOME_HEALTH", cbsa="Y",
        )
        output = apply_with_hash(
            oracle_connection, state_hash, lob="HOME_HEALTH", cbsa="Y",
        )
        assert "HASH MATCH: YES" in output
        assert "RESTORATION HASH MATCH: YES" in output
    finally:
        if renamed_context:
            cursor.execute("ALTER TABLE pfc_ctx_test_hold RENAME TO pfc_config_payor_context")
        for script in ACTION_SCRIPTS["install_value_codes"]:
            execute_script(cursor, script)
        oracle_connection.commit()
        cursor.close()
