from __future__ import annotations

import os
import re
from pathlib import Path

import oracledb
import pytest

from backend.tests.test_production_database_boundary import (
    READ_ONLY_FORBIDDEN,
    TOOL_OWNED_ORACLE_OBJECTS,
    executable_mutations_found,
    executable_sql,
    words_found,
)
from database.run_poc import connect, strip_block_comments
from database.tests.test_production_plan_guid_relationship import (
    MULTI_PAYOR,
    PAYOR_TYPE,
    PFC_PLAN_A,
    PLAN_A,
    insert_synthetic_cases,
)


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = (
    ROOT / "database" / "production_tests" /
    "14_claim_config_reference_capture_readonly.sql"
)

DUPLICATE_PLAN_PFC = "14B00000-0000-0000-0000-000000000001"
DUAL_EXACT_HER = "14F00000-0000-0000-0000-000000000001"
DUAL_NULL_HER = "14F00000-0000-0000-0000-000000000002"
EXACT_ONE_HER = "14F00000-0000-0000-0000-000000000003"
EXACT_TWO_HER = "14F00000-0000-0000-0000-000000000004"
NULL_ONE_HER = "14F00000-0000-0000-0000-000000000005"
NULL_TWO_HER = "14F00000-0000-0000-0000-000000000006"


def script_statements() -> list[str]:
    text = strip_block_comments(SCRIPT_PATH.read_text(encoding="utf-8"))
    statements: list[str] = []
    lines: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not lines and (
            not line or line.startswith("--") or line.upper().startswith("SET ")
        ):
            continue
        lines.append(raw_line)
        if line.endswith(";"):
            statements.append("\n".join(lines).rstrip()[:-1])
            lines = []
    assert not lines
    return statements


def execute_capture(
    connection: oracledb.Connection,
) -> list[tuple[list[str], list[dict[str, object]]]]:
    result_sets = []
    with connection.cursor() as cursor:
        for statement in script_statements():
            cursor.execute(statement)
            columns = [column[0].lower() for column in cursor.description]
            rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
            result_sets.append((columns, rows))
    return result_sets


def insert_additional_reference_cases(connection: oracledb.Connection) -> None:
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO pfc (
                pfc_guid, payor_guid, billing_form_type_code,
                billing_form_code, default_media_type, form_template_guid,
                plan_guid, type_of_bill, user_form_template_guid,
                start_date, end_date, cpd_start_date, cpd_end_date,
                rec_ent_date, rec_ent_user, rec_mod_date, rec_mod_user
            )
            SELECT
                :new_pfc_guid, payor_guid, billing_form_type_code,
                billing_form_code, default_media_type, form_template_guid,
                plan_guid, type_of_bill, user_form_template_guid,
                start_date, end_date, cpd_start_date, cpd_end_date,
                rec_ent_date, rec_ent_user, rec_mod_date, rec_mod_user
            FROM pfc
            WHERE pfc_guid = :source_pfc_guid
            """,
            new_pfc_guid=DUPLICATE_PLAN_PFC,
            source_pfc_guid=PFC_PLAN_A,
        )

        rows = [
            (DUAL_EXACT_HER, "SYN_DUAL", PLAN_A),
            (DUAL_NULL_HER, "SYN_DUAL", None),
            (EXACT_ONE_HER, "SYN_MULTI_EXACT", PLAN_A),
            (EXACT_TWO_HER, "SYN_MULTI_EXACT", PLAN_A),
            (NULL_ONE_HER, "SYN_MULTI_NULL", None),
            (NULL_TWO_HER, "SYN_MULTI_NULL", None),
        ]
        cursor.executemany(
            """
            INSERT INTO hcfa_electronic_records (
                electronic_rec_guid, loop_id, contiguity_ind,
                billing_form_code, record_name, record_type_code, record_size,
                mandatory_ind, req_for_claim_ind, payor_type_guid, payor_guid,
                plan_guid, type_of_bill, detail_ind, max_number, invoice_ind,
                form_template_guid, carry_forward_ind, max_carry_forward,
                sto_proc_name, user_form_template_guid, notes,
                rec_ent_date, rec_ent_user, include_record_data_onclaim
            ) VALUES (
                :her_guid, '2300', 'Y', '837I_5010',
                'Synthetic reference capture', :record_type, 100,
                'N', 'N', :payor_type, :payor_guid, :plan_guid, NULL,
                'N', '1', 'N', NULL, 'N', 0, 'RETURN_0', NULL,
                'Synthetic reference capture fixture',
                DATE '2026-01-01', 'SYNTHETIC', 'Y'
            )
            """,
            [
                {
                    "her_guid": row[0],
                    "record_type": row[1],
                    "plan_guid": row[2],
                    "payor_type": PAYOR_TYPE,
                    "payor_guid": MULTI_PAYOR,
                }
                for row in rows
            ],
        )


@pytest.fixture
def oracle_connection():
    connection = connect()
    host = (os.getenv("ORACLE_HOST") or "").lower()
    service = os.getenv("ORACLE_SERVICE_NAME") or os.getenv("ORACLE_SERVICE")
    if host not in {"localhost", "127.0.0.1", "::1"} or service != "FREEPDB1":
        connection.close()
        pytest.skip(
            "Reference capture integration is restricted to local loopback "
            "Oracle FREEPDB1."
        )
    try:
        insert_synthetic_cases(connection)
        insert_additional_reference_cases(connection)
        yield connection
    finally:
        connection.rollback()
        connection.close()


def test_script_14_static_read_only_and_bounded_contract() -> None:
    text = SCRIPT_PATH.read_text(encoding="utf-8")
    sql = executable_sql(text)
    assert "PRODUCTION HARNESS CLASS: READ_ONLY" in text
    assert "STANDALONE: YES" in text
    assert "TOOL-OWNED OBJECT DEPENDENCIES: NONE" in text
    assert not executable_mutations_found(sql, READ_ONLY_FORBIDDEN)
    assert not words_found(sql, TOOL_OWNED_ORACLE_OBJECTS)
    assert not re.search(r"\b(?:FOR\s+UPDATE|LOCK\s+TABLE)\b", sql, re.I)
    assert not re.search(r"&{1,2}[A-Za-z_][A-Za-z0-9_$#]*", sql)
    assert "EXECUTE IMMEDIATE" not in sql.upper()
    assert "r.representative_rank <= 25" in text

    eligible_section = text[
        text.index("eligible_pfcs AS (", text.index("3-10.")):
        text.index("),\npayor_hers AS (", text.index("3-10."))
    ]
    assert "p.cpd_start_date" in eligible_section
    assert not re.search(r"cpd_start_date\s*(?:<=|<|=|>=|>)", eligible_section, re.I)
    assert "p.default_media_type = 'E'" in eligible_section
    assert "p.user_form_template_guid IS NULL" in eligible_section
    for guid in (
        "E7BFA6270CF163DEE030007F010072AC",
        "9C3D46EEE7DB42B8AAE82B7A1038E223",
        "901B7182232A47EDAD5AB6B02F90F84C",
        "D9E9C52782F54AA29B27A058FCB6F412",
    ):
        assert guid in eligible_section


def test_script_14_executes_and_captures_reference_patterns(
    oracle_connection,
) -> None:
    result_sets = execute_capture(oracle_connection)
    assert len(result_sets) == 3

    _, schema_rows = result_sets[0]
    assert {row["table_name"] for row in schema_rows} >= {
        "PAYORS", "PFC", "HCFA_ELECTRONIC_RECORDS",
        "HCFA_ELECTRONIC_FIELDS",
    }
    assert any(
        row["table_name"] == "HCFA_ELECTRONIC_RECORDS"
        and row["column_name"] == "PLAN_GUID"
        for row in schema_rows
    )

    _, relationship_rows = result_sets[1]
    checks = {
        row["relationship_name"]: row
        for row in relationship_rows
        if row["metadata_kind"] == "LOGICAL_RELATIONSHIP_CHECK"
    }
    assert checks.keys() >= {"PFC_PAYOR", "HER_PAYOR", "HEF_HER"}
    assert all(
        row["declaration_status"] in {
            "DECLARED_FOREIGN_KEY_FOUND", "NO_DECLARED_FOREIGN_KEY_FOUND",
        }
        for row in checks.values()
    )

    _, pattern_rows = result_sets[2]
    sections = {row["output_section"] for row in pattern_rows}
    assert sections == {
        "PFC_STRUCTURAL_PATTERNS",
        "HER_STRUCTURAL_PATTERNS",
        "PFC_HER_PLAN_PATTERNS",
        "EXACT_VS_NULL_FALLBACK_PATTERNS",
        "TEMPLATE_CONTEXT_PATTERNS",
        "HER_HEF_RELATIONSHIP_PATTERNS",
        "RECORD_TYPE_PATTERNS",
        "REPRESENTATIVE_CONTEXTS",
    }

    relationship_categories = {
        row["relationship_category"] for row in pattern_rows
        if row["pattern_scope"] == "TEMPLATE_VALID_RELATIONSHIP_PAIRS"
    }
    assert relationship_categories >= {
        "EXACT_PLAN", "NULL_HER_FOR_PLAN_PFC", "OTHER_PLAN_HER",
        "POPULATED_HER_FOR_NO_PLAN_PFC",
    }

    fallback_rows = [
        row for row in pattern_rows
        if row["output_section"] == "EXACT_VS_NULL_FALLBACK_PATTERNS"
    ]
    assert {row["fallback_pattern"] for row in fallback_rows} >= {
        "A_EXACT_PLAN_ONLY", "B_NULL_FALLBACK_ONLY", "C_EXACT_AND_NULL",
    }
    assert any(
        row["multiple_exact_candidate_identity_count"] > 0
        for row in fallback_rows
    )
    assert any(
        row["multiple_null_candidate_identity_count"] > 0
        for row in fallback_rows
    )

    template_statuses = {
        row["template_context_status"] for row in pattern_rows
        if row["output_section"] == "TEMPLATE_CONTEXT_PATTERNS"
    }
    assert template_statuses >= {
        "BILLING_FORM_VALID", "FORM_TEMPLATE_VALID",
        "USER_TEMPLATE_VALID", "STALE_TEMPLATE_ASSOCIATION",
    }

    topology_categories = {
        row["pattern_category"] for row in pattern_rows
        if row["pattern_scope"] == "PAYOR_PFC_TOPOLOGY"
    }
    assert "MULTIPLE_PFCS_SAME_POPULATED_PLAN" in topology_categories
    assert any(
        row["pattern_category"] == "MULTIPLE_PFCS_SAME_POPULATED_PLAN"
        and row["payor_count"] > 0
        for row in pattern_rows
    )

    hef_rows = [
        row for row in pattern_rows
        if row["output_section"] == "HER_HEF_RELATIONSHIP_PATTERNS"
        and row["pattern_scope"] == "HEF_COUNT_DISTRIBUTION"
    ]
    assert {row["hef_count_bucket"] for row in hef_rows} >= {"0", "1"}

    record_types = {
        row["record_type_code"] for row in pattern_rows
        if row["output_section"] == "RECORD_TYPE_PATTERNS"
    }
    assert {"SYN_DUAL", "SYN_MULTI_EXACT", "SYN_MULTI_NULL"} <= record_types

    representatives = [
        row for row in pattern_rows
        if row["output_section"] == "REPRESENTATIVE_CONTEXTS"
    ]
    assert 0 < len(representatives) <= 25
    reasons = {row["representative_reason"] for row in representatives}
    assert "SAME_IDENTITY_EXACT_AND_NULL" in reasons
    assert "MULTIPLE_EXACT_CANDIDATES" in reasons
    assert "MULTIPLE_NULL_FALLBACK_CANDIDATES" in reasons
    assert all(row["representative_rank"] <= 25 for row in representatives)
