"""Local Oracle validation regressions; synthetic setup and every change roll back."""

import json
import os

import oracledb
import pytest

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.rebuild_hierarchy import fingerprint, insert_rows, procedure_row
from database.maintenance.seed_payor_plans import apply_option, change, structured_apply
from database.tests.plan_fixtures import PAYORS, database_state, plan, seed


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_VALIDATION") != "1",
    reason="Set RUN_ORACLE_VALIDATION=1 for local rollback-only validation tests",
)

TAXONOMY = "B2000A0030PRV080"
AUDIT_COLUMNS = {"electronic_rec_guid", "rec_ent_date", "rec_ent_user", "rec_mod_date", "rec_mod_user"}


@pytest.fixture
def oracle_cursor():
    assert get_oracle_settings().host.lower() in {"localhost", "127.0.0.1", "::1"}, "Local synthetic tests only"
    with create_connection() as connection:
        with connection.cursor() as cursor:
            before = fingerprint(database_state(cursor))
            try:
                yield cursor
            finally:
                connection.rollback()
                assert fingerprint(database_state(cursor)) == before, "Configuration and plan ownership must be restored"


@pytest.fixture
def scenario(oracle_cursor):
    seed(oracle_cursor)
    return oracle_cursor


def record_unit(cursor, payor, selected_plan, record_type=TAXONOMY):
    cursor.execute("""
        SELECT * FROM hcfa_electronic_records
        WHERE payor_guid=:payor AND record_type_code=:record_type
          AND (plan_guid=:selected_plan OR (plan_guid IS NULL AND :selected_plan IS NULL))
    """, payor=payor, selected_plan=selected_plan, record_type=record_type)
    columns = [description[0].lower() for description in cursor.description]
    rows = cursor.fetchall()
    assert len(rows) == 1
    her = dict(zip(columns, rows[0]))
    cursor.execute("SELECT * FROM hcfa_electronic_fields WHERE electronic_rec_guid=:guid", guid=her["electronic_rec_guid"])
    columns = [description[0].lower() for description in cursor.description]
    return her, [dict(zip(columns, row)) for row in cursor]


def business_row(row):
    return {key: value for key, value in row.items() if key not in AUDIT_COLUMNS}


def field_multiset(fields):
    return fingerprint({"fields": [business_row(field) for field in fields]})


def add_unmanaged_field(cursor, source_fields):
    insert_rows(cursor, "HCFA_ELECTRONIC_FIELDS", [{
        **source_fields[0],
        "field_number": "99",
        "field_name": "SYN_VALIDATION_UNMANAGED",
        "order_num": 99,
        "sto_proc_name": "SYN_UNMANAGED_PROC",
        "hard_coded_data": "Synthetic preserved value",
    }])


@pytest.mark.parametrize("mode", [None, "", "   ", "INVALID", "PREVIEWX", "APPLY_EXTRA", "X" * 128])
@pytest.mark.parametrize("use_valid_hash", [False, True], ids=["without-hash", "valid-hash"])
def test_invalid_mode_is_rejected_before_any_mutation(scenario, mode, use_valid_hash):
    preview = change(scenario, PAYORS[0], plan(0, 1), "PROVIDER_TAXONOMY_OFF")
    assert preview["target_action"] == "REBUILD_OVERRIDE"
    before = fingerprint(database_state(scenario))
    try:
        with pytest.raises(oracledb.DatabaseError, match="ORA-20030"):
            change(scenario, PAYORS[0], plan(0, 1), "PROVIDER_TAXONOMY_OFF", mode,
                   preview["state_hash"] if use_valid_hash else None)
    finally:
        assert fingerprint(database_state(scenario)) == before, "An invalid mode must not change HER, HEF, PFC, or ownership"


@pytest.mark.parametrize("mode", [None, "   ", "PREVIEW_TOO_LONG"])
def test_invalid_mode_precedes_option_and_context_resolution(oracle_cursor, mode):
    before = fingerprint(database_state(oracle_cursor))
    with pytest.raises(oracledb.DatabaseError, match="ORA-20030"):
        change(oracle_cursor, None, None, "SYN_UNKNOWN_OPTION", mode)
    assert fingerprint(database_state(oracle_cursor)) == before


@pytest.mark.parametrize("preview_mode,apply_mode", [("PREVIEW", "APPLY"), (" preview ", " apply "), ("pReViEw", "aPpLy")])
def test_valid_modes_keep_case_and_space_normalization(scenario, preview_mode, apply_mode):
    before = fingerprint(database_state(scenario))
    preview = change(scenario, PAYORS[0], plan(0, 1), "PROVIDER_TAXONOMY_OFF", preview_mode)
    assert preview["status"] == "PREVIEW"
    assert fingerprint(database_state(scenario)) == before
    result = change(scenario, PAYORS[0], plan(0, 1), "PROVIDER_TAXONOMY_OFF", apply_mode, preview["state_hash"])
    assert result["status"] == "APPLIED"
    current = procedure_row(scenario, "pfc_get_current_config", [PAYORS[0], plan(0, 1), "81"])
    assert current["effective_option_code"] == "PROVIDER_TAXONOMY_OFF"


@pytest.mark.parametrize("state_hash,error_code", [(None, "ORA-20035"), ("0" * 64, "ORA-20036")])
def test_valid_apply_still_requires_a_current_preview_hash(scenario, state_hash, error_code):
    before = fingerprint(database_state(scenario))
    with pytest.raises(oracledb.DatabaseError, match=error_code):
        change(scenario, PAYORS[0], plan(0, 1), "PROVIDER_TAXONOMY_OFF", " apply ", state_hash)
    assert fingerprint(database_state(scenario)) == before


@pytest.mark.parametrize("procedure,mandatory,expected", [
    (None, "Y", "N"), ("", "Y", "N"), (" ", "Y", "N"), ("   ", None, "N"),
    ("RETURN_0", "Y", "N"), ("SYN_CONDITIONAL", "Y", "N"),
    ("RETURN_1", "Y", "Y"), ("RETURN_1", "N", "N"),
    (" return_1 ", "Y", "Y"), ("return_1", None, None),
])
def test_mandatory_normalization_treats_blank_as_null_and_preserves_return_1(oracle_cursor, procedure, mandatory, expected):
    actual = oracle_cursor.var(str, size=1)
    actual_procedure = oracle_cursor.var(str, size=30)
    notes = oracle_cursor.var(str, size=100)
    oracle_cursor.execute("""
        DECLARE
            l_her hcfa_electronic_records%ROWTYPE;
        BEGIN
            l_her.sto_proc_name := :procedure;
            l_her.mandatory_ind := :mandatory;
            l_her.notes := 'Synthetic untouched notes';
            pfc_config_internal.apply_her_safety_invariants(l_her);
            :actual := l_her.mandatory_ind;
            :actual_procedure := l_her.sto_proc_name;
            :notes := l_her.notes;
        END;
    """, procedure=procedure, mandatory=mandatory, actual=actual,
        actual_procedure=actual_procedure, notes=notes)
    assert actual.getvalue() == expected
    assert actual_procedure.getvalue() == (procedure or None)
    assert notes.getvalue() == "Synthetic untouched notes"


def test_explicit_option_repairs_blank_parent_without_changing_source_or_unmanaged_fields(scenario):
    parent, fields = record_unit(scenario, PAYORS[0], None)
    scenario.execute("UPDATE hcfa_electronic_records SET sto_proc_name='   ', mandatory_ind='Y' WHERE electronic_rec_guid=:guid", guid=parent["electronic_rec_guid"])
    add_unmanaged_field(scenario, fields)
    source, source_fields = record_unit(scenario, PAYORS[0], None)
    apply_option(scenario, PAYORS[0], plan(0, 1), "PROVIDER_TAXONOMY_OFF")
    target, target_fields = record_unit(scenario, PAYORS[0], plan(0, 1))
    assert business_row(target) == {
        **business_row(source), "plan_guid": plan(0, 1), "sto_proc_name": "RETURN_0",
        "mandatory_ind": "N", "carry_forward_ind": None, "include_record_data_onclaim": "Y",
    }
    assert field_multiset(target_fields) == field_multiset(source_fields)
    assert record_unit(scenario, PAYORS[0], None) == (source, source_fields)


@pytest.mark.parametrize("procedure", [None, "   ", "RETURN_0"])
def test_default_remains_blocked_for_unsafe_inherited_records(scenario, procedure):
    structured_apply(scenario, "pfc_remarks_api", [PAYORS[0], None, "CUSTOM", "Synthetic parent remark"])
    parent, _ = record_unit(scenario, PAYORS[0], None, "D23001900NTE182")
    scenario.execute("UPDATE hcfa_electronic_records SET sto_proc_name=:procedure, mandatory_ind='Y' WHERE electronic_rec_guid=:guid",
                     procedure=procedure, guid=parent["electronic_rec_guid"])
    before = fingerprint(database_state(scenario))
    with pytest.raises(oracledb.DatabaseError, match="ORA-20012"):
        structured_apply(scenario, "pfc_remarks_api", [PAYORS[0], plan(0, 1), "DEFAULT", None])
    assert fingerprint(database_state(scenario)) == before


def copy(scenario, mode="PREVIEW", state_hash=None):
    output = scenario.var(oracledb.DB_TYPE_CLOB)
    scenario.execute("""BEGIN pfc_copy.run_copy(
        :source, :source_plan, :destination, :mode, 'SYN_VALIDATION_TEST', :state_hash, :output
    ); END;""", source=PAYORS[0], source_plan=plan(0, 2), destination=PAYORS[1],
        mode=mode, state_hash=state_hash, output=output)
    return json.loads(output.getvalue().read())


def test_copy_normalizes_blank_procedure_and_preserves_complete_source(scenario):
    # Align this transaction's isolated destination with the source's copy prerequisites.
    scenario.execute("UPDATE pfc_config_payor_context SET line_of_business='HOME_HEALTH' WHERE payor_guid=:payor", payor=PAYORS[1])
    scenario.execute("UPDATE payors SET payor_type_guid=(SELECT payor_type_guid FROM payors WHERE payor_guid=:source) WHERE payor_guid=:destination",
                     source=PAYORS[0], destination=PAYORS[1])
    source, fields = record_unit(scenario, PAYORS[0], plan(0, 2))
    scenario.execute("UPDATE hcfa_electronic_records SET sto_proc_name='   ', mandatory_ind='Y' WHERE electronic_rec_guid=:guid", guid=source["electronic_rec_guid"])
    add_unmanaged_field(scenario, fields)
    source, source_fields = record_unit(scenario, PAYORS[0], plan(0, 2))
    before = database_state(scenario)
    preview = copy(scenario)
    assert preview["status"] == "READY" and preview["records_normalized"] > 0
    assert fingerprint(database_state(scenario)) == fingerprint(before)
    try:
        result = copy(scenario, "APPLY", preview["state_hash"])
    except oracledb.DatabaseError:
        # The old whitespace bug fails post-copy verification; even that failure
        # must restore complete HER/HEF units and every destination association.
        assert fingerprint(database_state(scenario)) == fingerprint(before)
        raise
    assert result["status"] == "APPLIED"
    target, target_fields = record_unit(scenario, PAYORS[1], None)
    assert business_row(target) == {
        **business_row(source), "payor_guid": PAYORS[1], "plan_guid": None,
        "mandatory_ind": "N", "carry_forward_ind": None, "include_record_data_onclaim": "Y",
    }
    assert field_multiset(target_fields) == field_multiset(source_fields)
    after = database_state(scenario)
    destination_guids = {row["electronic_rec_guid"] for row in before["HCFA_ELECTRONIC_RECORDS"] if row["payor_guid"] == PAYORS[1]}
    destination_guids.update(row["electronic_rec_guid"] for row in after["HCFA_ELECTRONIC_RECORDS"] if row["payor_guid"] == PAYORS[1])
    for table in before:
        if table == "HCFA_ELECTRONIC_FIELDS":
            preserved = lambda row: row["electronic_rec_guid"] not in destination_guids
        else:
            preserved = lambda row: row.get("payor_guid") != PAYORS[1]
        assert fingerprint({table: list(filter(preserved, before[table]))}) == fingerprint({table: list(filter(preserved, after[table]))})
    assert not any(row["payor_guid"] == PAYORS[1] and row["plan_guid"] is not None for row in after["HCFA_ELECTRONIC_RECORDS"])
