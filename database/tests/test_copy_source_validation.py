"""Source-only Copy checks use isolated synthetic data and always roll back."""

import json
import os
from pathlib import Path
from uuid import uuid4

import oracledb
import pytest

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.rebuild_hierarchy import fingerprint, insert_rows
from database.tests.plan_fixtures import PAYORS, database_state, pfc, plan, seed


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_COPY_SOURCE") != "1",
    reason="Set RUN_ORACLE_COPY_SOURCE=1 for local rollback-only Copy source tests",
)

RECORD_TYPE = "SYN_SOURCE_CHECK"
AUDIT_USER = "SYN_COPY_SOURCE_TEST"


@pytest.fixture
def scenario():
    assert get_oracle_settings().host.lower() in {"localhost", "127.0.0.1", "::1"}, "Local synthetic tests only"
    with create_connection() as connection:
        with connection.cursor() as cursor:
            before = fingerprint(database_state(cursor))
            try:
                seed(cursor)
                # The second isolated payor supplies a compatible destination
                # solely to compare preflight with the existing real Preview.
                cursor.execute("""UPDATE payors SET payor_type_guid=(
                    SELECT payor_type_guid FROM payors WHERE payor_guid=:source)
                    WHERE payor_guid=:destination""", source=PAYORS[0], destination=PAYORS[1])
                cursor.execute("""UPDATE pfc_config_payor_context SET line_of_business='HOME_HEALTH'
                    WHERE payor_guid=:destination""", destination=PAYORS[1])
                yield cursor
            finally:
                connection.rollback()
                assert fingerprint(database_state(cursor)) == before, "Configuration and plan ownership must be restored"


def validate(cursor, selected_plan=None, source=PAYORS[0], audit_user=AUDIT_USER):
    before = fingerprint(database_state(cursor))
    try:
        cursor.execute("BEGIN pfc_copy.validate_source(:source,:plan,:audit_user); END;",
                       source=source, plan=selected_plan, audit_user=audit_user)
    finally:
        assert fingerprint(database_state(cursor)) == before, "Source validation must be read-only"


def preview(cursor, selected_plan=None, source=PAYORS[0], audit_user=AUDIT_USER):
    before = fingerprint(database_state(cursor))
    try:
        output = cursor.var(oracledb.DB_TYPE_CLOB)
        cursor.execute("BEGIN pfc_copy.run_copy(:source,:plan,:destination,'PREVIEW',:audit_user,NULL,:result); END;",
                       source=source, plan=selected_plan, destination=PAYORS[1], audit_user=audit_user, result=output)
        raw = output.getvalue()
        return json.loads(raw.read() if hasattr(raw, "read") else raw)
    finally:
        assert fingerprint(database_state(cursor)) == before, "Copy Preview must be read-only"


def add_record(cursor, *, owner=PAYORS[0], selected_plan=None, procedure="RETURN_0", mandatory="N", **overrides):
    cursor.execute("""SELECT * FROM hcfa_electronic_records
        WHERE payor_guid=:source AND plan_guid IS NULL AND record_type_code='B2000A0030PRV080'""", source=PAYORS[0])
    rows = cursor.fetchall()
    assert len(rows) == 1
    row = dict(zip((column[0].lower() for column in cursor.description), rows[0]))
    parent = row["electronic_rec_guid"]
    row.update(electronic_rec_guid=str(uuid4()).upper(), record_type_code=RECORD_TYPE,
               payor_guid=owner, plan_guid=selected_plan, payor_type_guid=None,
               form_template_guid=None, user_form_template_guid=None,
               sto_proc_name=procedure, mandatory_ind=mandatory,
               carry_forward_ind=None, include_record_data_onclaim="Y", **overrides)
    insert_rows(cursor, "HCFA_ELECTRONIC_RECORDS", [row])
    cursor.execute("SELECT * FROM hcfa_electronic_fields WHERE electronic_rec_guid=:parent", parent=parent)
    columns = [column[0].lower() for column in cursor.description]
    fields = [dict(zip(columns, values)) for values in cursor.fetchall()]
    insert_rows(cursor, "HCFA_ELECTRONIC_FIELDS", [{**field, "electronic_rec_guid": row["electronic_rec_guid"]} for field in fields])
    return row["electronic_rec_guid"]


def assert_rejected_like_preview(cursor, code, **request):
    # Compare with the established Copy implementation before invoking the new
    # endpoint; this also guards against stricter source-only eligibility rules.
    with pytest.raises(oracledb.DatabaseError, match=f"ORA-{code}"):
        preview(cursor, **request)
    with pytest.raises(oracledb.DatabaseError, match=f"ORA-{code}"):
        validate(cursor, **request)


@pytest.mark.parametrize("selected_plan", [None, plan(0, 1), plan(0, 2), plan(0, 3)])
def test_valid_payor_and_owned_plan_sources_match_preview(scenario, selected_plan):
    assert preview(scenario, selected_plan)["status"] in {"READY", "NO_CHANGE"}
    validate(scenario, selected_plan)


@pytest.mark.parametrize("audit_user", [None, "", "   "])
def test_blank_audit_identity_is_rejected(scenario, audit_user):
    assert_rejected_like_preview(scenario, "20100", audit_user=audit_user)


@pytest.mark.parametrize("source,selected_plan", [(None, None), ("SYN_MISSING_PAYOR", None),
                                                   (PAYORS[0], plan(1, 1)), (PAYORS[0], "SYN_MISSING_PLAN")])
def test_missing_context_and_other_payors_plan_are_rejected(scenario, source, selected_plan):
    assert_rejected_like_preview(scenario, "20104", source=source, selected_plan=selected_plan)


def test_missing_line_of_business_is_rejected(scenario):
    scenario.execute("DELETE FROM pfc_config_payor_context WHERE payor_guid=:source", source=PAYORS[0])
    assert_rejected_like_preview(scenario, "20053")


# Local PFC.REC_ENT_DATE is NOT NULL, so a missing-date fixture cannot be
# constructed without relaxing the schema. Keep the shared resolver guard and
# test only invalid states this rollback-only fixture can actually create.
@pytest.mark.parametrize("case,code", [("missing", "20104"), ("tied", "20104"), ("billing-form", "20103")])
def test_invalid_source_pfc_is_rejected(scenario, case, code):
    if case == "missing":
        scenario.execute("DELETE FROM pfc WHERE pfc_guid=:guid", guid=pfc(0, 1))
    elif case == "billing-form":
        scenario.execute("UPDATE pfc SET billing_form_code='837P_5010' WHERE pfc_guid=:guid", guid=pfc(0, 1))
    else:
        scenario.execute("SELECT * FROM pfc WHERE pfc_guid=:guid", guid=pfc(0, 1))
        row = dict(zip((column[0].lower() for column in scenario.description), scenario.fetchone()))
        insert_rows(scenario, "PFC", [{**row, "pfc_guid": str(uuid4()).upper()}])
    assert_rejected_like_preview(scenario, code, selected_plan=plan(0, 1))


@pytest.mark.parametrize("selected_plan", [None, plan(0, 1)])
def test_source_bill_type_records_are_rejected(scenario, selected_plan):
    add_record(scenario, selected_plan=selected_plan, type_of_bill="111")
    assert_rejected_like_preview(scenario, "20104", selected_plan=selected_plan)


@pytest.mark.parametrize("level", ["generic", "payor", "plan"])
def test_tied_effective_source_records_are_rejected(scenario, level):
    request_plan = plan(0, 1) if level == "plan" else None
    for _ in range(2):
        add_record(scenario, owner=None if level == "generic" else PAYORS[0], selected_plan=request_plan)
    assert_rejected_like_preview(scenario, "20104", selected_plan=request_plan)


@pytest.mark.parametrize("procedure", [None, "   ", "RETURN_0"])
def test_unsafe_effective_inherited_source_is_rejected(scenario, procedure):
    add_record(scenario, owner=None, procedure=procedure, mandatory="Y")
    assert_rejected_like_preview(scenario, "20012")


@pytest.mark.parametrize("selected_plan", [None, plan(0, 1)])
@pytest.mark.parametrize("procedure", [None, "   ", "RETURN_0"])
def test_unsafe_source_overrides_remain_eligible_for_copy_normalization(scenario, selected_plan, procedure):
    add_record(scenario, selected_plan=selected_plan, procedure=procedure, mandatory="Y")
    assert preview(scenario, selected_plan)["records_normalized"] > 0
    validate(scenario, selected_plan)


@pytest.mark.parametrize("shadowed_level", ["generic", "payor"])
def test_shadowed_ties_and_unsafe_records_do_not_block(scenario, shadowed_level):
    for _ in range(2):
        add_record(scenario, owner=None if shadowed_level == "generic" else PAYORS[0], mandatory="Y")
    selected_plan = plan(0, 1) if shadowed_level == "payor" else None
    add_record(scenario, selected_plan=selected_plan)
    assert preview(scenario, selected_plan)["status"] == "READY"
    validate(scenario, selected_plan)


def test_other_plan_bill_type_and_other_form_source_records_are_ignored(scenario):
    add_record(scenario, selected_plan=plan(0, 2), type_of_bill="111")
    add_record(scenario, billing_form_code="837P_5010", type_of_bill="111")
    assert preview(scenario, plan(0, 1))["status"] == "READY"
    validate(scenario, plan(0, 1))


def test_absent_effective_record_is_not_a_source_error(scenario):
    # A record type existing only for a different source plan is absent in both
    # effective configurations. Actual Copy permits that absence.
    add_record(scenario, selected_plan=plan(0, 2))
    assert preview(scenario, plan(0, 1))["status"] == "READY"
    validate(scenario, plan(0, 1))


def test_source_validation_runs_in_oracle_read_only_transaction():
    assert get_oracle_settings().host.lower() in {"localhost", "127.0.0.1", "::1"}, "Local synthetic tests only"
    # Use the stable original hierarchy source, never the editable plan/copy
    # demos, because uncommitted fixture setup cannot precede READ ONLY.
    seed_path = Path(__file__).resolve().parents[1] / "maintenance" / "hierarchy_seed.json"
    original = json.loads(seed_path.read_text(encoding="utf-8"))
    source = next(row["payor_guid"] for row in original["PFC"]
                  if row["plan_guid"] is None and row["user_form_template_guid"] is None)
    with create_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SET TRANSACTION READ ONLY")
            before = fingerprint(database_state(cursor))
            try:
                validate(cursor, source=source)
            finally:
                connection.rollback()
                assert fingerprint(database_state(cursor)) == before
