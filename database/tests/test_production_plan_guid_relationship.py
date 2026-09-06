from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path

import oracledb
import pytest

from database.run_poc import connect


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = (
    ROOT / "database" / "production_tests" /
    "13_plan_guid_relationship_readonly.sql"
)

MULTI_PAYOR = "13A00000-0000-0000-0000-000000000001"
SIMPLE_PAYOR = "13A00000-0000-0000-0000-000000000002"
PAYOR_TYPE = "13A00000-0000-0000-0000-000000000099"
FORM_A = "13D00000-0000-0000-0000-000000000001"
FORM_X = "13D00000-0000-0000-0000-000000000099"
USER_B = "13E00000-0000-0000-0000-000000000001"
PLAN_A = "13C00000-0000-0000-0000-000000000001"
PLAN_B = "13C00000-0000-0000-0000-000000000002"
PLAN_X = "13C00000-0000-0000-0000-000000000099"

PFC_NO_PLAN = "13B00000-0000-0000-0000-000000000001"
PFC_PLAN_A = "13B00000-0000-0000-0000-000000000002"
PFC_PLAN_B = "13B00000-0000-0000-0000-000000000003"
PFC_HOSPICE = "13B00000-0000-0000-0000-000000000004"
PFC_NON_ELECTRONIC = "13B00000-0000-0000-0000-000000000005"
PFC_SIMPLE = "13B00000-0000-0000-0000-000000000006"

HER_NULL = "13F00000-0000-0000-0000-000000000001"
HER_PLAN_A = "13F00000-0000-0000-0000-000000000002"
HER_PLAN_X = "13F00000-0000-0000-0000-000000000003"
HER_FORM = "13F00000-0000-0000-0000-000000000004"
HER_USER = "13F00000-0000-0000-0000-000000000005"
HER_STALE = "13F00000-0000-0000-0000-000000000006"
HER_TYPE_OF_BILL = "13F00000-0000-0000-0000-000000000007"
HER_SIMPLE = "13F00000-0000-0000-0000-000000000008"

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_PRODUCTION_HARNESS_INTEGRATION") != "1",
    reason="set RUN_ORACLE_PRODUCTION_HARNESS_INTEGRATION=1 for local Oracle harness tests",
)


def report_sql(payor_guid: str | None = None) -> str:
    text = SCRIPT_PATH.read_text(encoding="utf-8")
    if payor_guid is not None:
        old = "SELECT CAST(NULL AS VARCHAR2(36)) AS payor_guid"
        assert old in text
        text = text.replace(
            old, f"SELECT CAST('{payor_guid}' AS VARCHAR2(36)) AS payor_guid", 1
        )
    return text[text.index("WITH\n"):].rstrip().removesuffix(";")


def execute_report(
    connection: oracledb.Connection, payor_guid: str | None = None,
) -> tuple[list[str], list[dict[str, object]]]:
    with connection.cursor() as cursor:
        cursor.execute(report_sql(payor_guid))
        columns = [column[0].lower() for column in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
        return columns, rows


def insert_synthetic_cases(connection: oracledb.Connection) -> None:
    entered = datetime(2026, 1, 1)
    with connection.cursor() as cursor:
        cursor.executemany(
            """
            INSERT INTO payors (
                payor_guid, payor_type_guid, payor_name,
                rec_ent_date, rec_ent_user
            ) VALUES (:1, :2, :3, :4, :5)
            """,
            [
                (MULTI_PAYOR, PAYOR_TYPE, "Synthetic multi-plan discovery", entered, "SYNTHETIC"),
                (SIMPLE_PAYOR, PAYOR_TYPE, "Synthetic simple discovery", entered, "SYNTHETIC"),
            ],
        )

        pfc_rows = [
            (PFC_NO_PLAN, MULTI_PAYOR, FORM_A, None, None,
             datetime(1970, 1, 1), datetime(2099, 12, 31), "E"),
            (PFC_PLAN_A, MULTI_PAYOR, FORM_A, PLAN_A, USER_B,
             datetime(1970, 1, 1), datetime(2099, 12, 31), "E"),
            # A future CPD start remains eligible by design.
            (PFC_PLAN_B, MULTI_PAYOR, FORM_A, PLAN_B, USER_B,
             datetime(2098, 1, 1), datetime(2099, 12, 31), "E"),
            (PFC_HOSPICE, MULTI_PAYOR, FORM_A, PLAN_X,
             "E7BFA6270CF163DEE030007F010072AC",
             datetime(1970, 1, 1), datetime(2099, 12, 31), "E"),
            (PFC_NON_ELECTRONIC, MULTI_PAYOR, FORM_A, PLAN_X, None,
             datetime(1970, 1, 1), datetime(2099, 12, 31), "P"),
            (PFC_SIMPLE, SIMPLE_PAYOR, None, None, None,
             datetime(1970, 1, 1), datetime(2099, 12, 31), "E"),
        ]
        cursor.executemany(
            """
            INSERT INTO pfc (
                pfc_guid, payor_guid, billing_form_type_code,
                billing_form_code, default_media_type, form_template_guid,
                plan_guid, type_of_bill, user_form_template_guid,
                start_date, end_date, cpd_start_date, cpd_end_date,
                rec_ent_date, rec_ent_user, rec_mod_date, rec_mod_user
            ) VALUES (
                :pfc_guid, :payor_guid, 'I', '837I_5010', :media,
                :form_guid, :plan_guid, NULL, :user_guid,
                DATE '1970-01-01', NULL, :cpd_start, :cpd_end,
                DATE '2026-01-01', 'SYNTHETIC', NULL, NULL
            )
            """,
            [
                {
                    "pfc_guid": row[0], "payor_guid": row[1],
                    "form_guid": row[2], "plan_guid": row[3],
                    "user_guid": row[4], "cpd_start": row[5],
                    "cpd_end": row[6], "media": row[7],
                }
                for row in pfc_rows
            ],
        )

        her_rows = [
            (HER_NULL, MULTI_PAYOR, "SYN_PLAN_NULL", "Synthetic plan-null", None, None, None, None),
            (HER_PLAN_A, MULTI_PAYOR, "SYN_PLAN_A", "Synthetic exact plan", PLAN_A, None, None, None),
            (HER_PLAN_X, MULTI_PAYOR, "SYN_PLAN_X", "Synthetic different plan", PLAN_X, None, None, None),
            (HER_FORM, MULTI_PAYOR, "SYN_FORM", "Synthetic form template", None, FORM_A, None, None),
            (HER_USER, MULTI_PAYOR, "SYN_USER", "Synthetic user template", None, None, USER_B, None),
            (HER_STALE, MULTI_PAYOR, "SYN_STALE", "Synthetic stale template", None, FORM_X, None, None),
            (HER_TYPE_OF_BILL, MULTI_PAYOR, "SYN_TOB", "Synthetic type of bill", PLAN_A, None, None, "111"),
            (HER_SIMPLE, SIMPLE_PAYOR, "SYN_SIMPLE", "Synthetic simple context", None, None, None, None),
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
                :her_guid, '2300', 'Y', '837I_5010', :record_name,
                :record_type, 100, 'N', 'N', :payor_type, :payor_guid,
                :plan_guid, :type_of_bill, 'N', '1', 'N',
                :form_guid, 'N', 0, 'RETURN_0', :user_guid,
                'Synthetic discovery HER',
                DATE '2026-01-01', 'SYNTHETIC', 'Y'
            )
            """,
            [
                {
                    "her_guid": row[0], "payor_guid": row[1],
                    "record_type": row[2], "record_name": row[3],
                    "plan_guid": row[4], "form_guid": row[5],
                    "user_guid": row[6], "type_of_bill": row[7],
                    "payor_type": PAYOR_TYPE,
                }
                for row in her_rows
            ],
        )
        cursor.execute(
            """
            INSERT INTO hcfa_electronic_fields (
                field_number, electronic_rec_guid, field_name,
                record_type_code, pic, position_from, position_thru,
                detail_ind, rec_ent_date, rec_ent_user
            ) VALUES (
                '01', :her_guid, 'SYN01', 'SYN_PLAN_NULL', 'X(1)', 1, 1,
                'N', DATE '2026-01-01', 'SYNTHETIC'
            )
            """,
            her_guid=HER_NULL,
        )


@pytest.fixture
def oracle_connection():
    connection = connect()
    host = (os.getenv("ORACLE_HOST") or "").lower()
    service = os.getenv("ORACLE_SERVICE_NAME") or os.getenv("ORACLE_SERVICE")
    if host not in {"localhost", "127.0.0.1", "::1"} or service != "FREEPDB1":
        connection.close()
        pytest.fail(
            "Plan relationship integration tests are restricted to local "
            "loopback Oracle FREEPDB1."
        )
    try:
        insert_synthetic_cases(connection)
        yield connection
    finally:
        connection.rollback()
        connection.close()


def row_for(rows, section, *, pfc=None, her=None):
    return next(
        row for row in rows
        if row["output_section"] == section
        and (pfc is None or row["pfc_guid"] == pfc)
        and (her is None or row["her_electronic_rec_guid"] == her)
    )


@pytest.mark.parametrize("payor_guid", [None, SIMPLE_PAYOR])
def test_final_wrapped_compound_query_executes_with_qualified_order_by(
    oracle_connection, payor_guid,
):
    sql = report_sql(payor_guid)
    assert ") report_output\nORDER BY" in sql
    assert "report_output.output_order" in sql

    with oracle_connection.cursor() as cursor:
        cursor.execute(sql)
        rows = cursor.fetchall()
        assert rows
        if payor_guid is not None:
            payor_index = next(
                index for index, column in enumerate(cursor.description)
                if column[0].lower() == "payor_guid"
            )
            assert {row[payor_index] for row in rows} == {payor_guid}


def test_discovery_and_detail_classify_all_synthetic_relationships(
    oracle_connection,
):
    columns, rows = execute_report(oracle_connection)
    assert len(columns) == 62

    discovery_rows = [
        row for row in rows if row["output_section"] == "PAYOR_DISCOVERY"
    ]
    multi = next(row for row in discovery_rows if row["payor_guid"] == MULTI_PAYOR)
    simple = next(row for row in discovery_rows if row["payor_guid"] == SIMPLE_PAYOR)
    assert multi["eligible_pfc_count"] == 3
    assert multi["no_plan_pfc_count"] == 1
    assert multi["plan_pfc_count"] == 2
    assert multi["distinct_plan_guid_count"] == 2
    assert multi["payor_her_count"] == 7
    assert multi["valid_template_her_count"] == 6
    assert multi["stale_template_her_count"] == 1
    assert multi["her_matching_multiple_pfcs_count"] == 6
    assert multi["her_with_no_valid_pfc_count"] == 1
    assert multi["discovery_classification"] == "HIGH_VALUE_MULTI_PLAN_MIXED"
    assert multi["discovery_priority"] < simple["discovery_priority"]

    pfc_rows = [row for row in rows if row["output_section"] == "PFC_SUMMARY"]
    assert {row["pfc_guid"] for row in pfc_rows if row["payor_guid"] == MULTI_PAYOR} == {
        PFC_NO_PLAN, PFC_PLAN_A, PFC_PLAN_B,
    }
    assert PFC_HOSPICE not in {row["pfc_guid"] for row in pfc_rows}
    assert PFC_NON_ELECTRONIC not in {row["pfc_guid"] for row in pfc_rows}
    assert row_for(rows, "PFC_SUMMARY", pfc=PFC_PLAN_B)["cpd_start_date"].year == 2098

    no_plan_null = row_for(rows, "HER_DETAIL", pfc=PFC_NO_PLAN, her=HER_NULL)
    assert no_plan_null["template_context_status"] == "BILLING_FORM_VALID"
    assert no_plan_null["plan_context_status"] == "EXACT_PLAN_MATCH"
    assert no_plan_null["ownership_status"] == "VALID_EXACT_PLAN"
    assert no_plan_null["eligible_pfc_match_count"] == 3
    assert no_plan_null["plan_null_pfc_context_count"] == 2
    assert no_plan_null["pfc_context_classification"] == "MULTIPLE_PFC_CONTEXTS"
    assert no_plan_null["hef_count"] == 1

    plan_exact = row_for(rows, "HER_DETAIL", pfc=PFC_PLAN_A, her=HER_PLAN_A)
    assert plan_exact["plan_context_status"] == "EXACT_PLAN_MATCH"
    assert plan_exact["ownership_status"] == "VALID_EXACT_PLAN"
    assert plan_exact["exact_plan_pfc_match_count"] == 1

    assert row_for(rows, "HER_DETAIL", pfc=PFC_PLAN_A, her=HER_NULL)[
        "plan_context_status"
    ] == "HER_PLAN_NULL_FOR_PLAN_PFC"
    assert row_for(rows, "HER_DETAIL", pfc=PFC_PLAN_A, her=HER_NULL)[
        "ownership_status"
    ] == "VALID_BUT_HER_PLAN_NULL"
    assert row_for(rows, "HER_DETAIL", pfc=PFC_PLAN_B, her=HER_PLAN_A)[
        "plan_context_status"
    ] == "HER_PLAN_DIFFERENT"
    assert row_for(rows, "HER_DETAIL", pfc=PFC_NO_PLAN, her=HER_PLAN_A)[
        "plan_context_status"
    ] == "HER_PLAN_POPULATED_FOR_NO_PLAN_PFC"

    assert row_for(rows, "HER_DETAIL", pfc=PFC_NO_PLAN, her=HER_FORM)[
        "template_context_status"
    ] == "FORM_TEMPLATE_VALID"
    assert row_for(rows, "HER_DETAIL", pfc=PFC_PLAN_A, her=HER_USER)[
        "template_context_status"
    ] == "USER_TEMPLATE_VALID"
    stale = row_for(rows, "HER_DETAIL", pfc=PFC_PLAN_A, her=HER_STALE)
    assert stale["template_context_status"] == "STALE_TEMPLATE_ASSOCIATION"
    assert stale["ownership_status"] == "INVALID_TEMPLATE_CONTEXT"
    assert stale["pfc_context_classification"] == "NO_VALID_PFC_CONTEXT"

    type_of_bill = row_for(
        rows, "HER_DETAIL", pfc=PFC_PLAN_A, her=HER_TYPE_OF_BILL
    )
    assert type_of_bill["her_type_of_bill"] == "111"
    assert type_of_bill["ownership_status"] == "HER_TYPE_OF_BILL_PRESENT"
    assert len({row["payor_guid"] for row in pfc_rows}) <= 25


def test_focused_mode_returns_only_the_requested_payor_with_full_detail(
    oracle_connection,
):
    _, rows = execute_report(oracle_connection, SIMPLE_PAYOR)
    assert {row["output_section"] for row in rows} == {
        "PAYOR_DISCOVERY", "PFC_SUMMARY", "HER_DETAIL",
    }
    assert {row["payor_guid"] for row in rows} == {SIMPLE_PAYOR}
    detail = row_for(rows, "HER_DETAIL", pfc=PFC_SIMPLE, her=HER_SIMPLE)
    assert detail["plan_context_status"] == "EXACT_PLAN_MATCH"
    assert detail["template_context_status"] == "BILLING_FORM_VALID"
    assert detail["ownership_status"] == "VALID_EXACT_PLAN"
    assert detail["pfc_context_classification"] == "UNIQUE_PFC_CONTEXT"
