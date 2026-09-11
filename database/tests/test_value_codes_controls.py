"""Explicit checkbox states coexist with legacy Default requests; all DML rolls back."""

import os

import oracledb
import pytest

from database.maintenance.rebuild_hierarchy import fingerprint
from database.tests.plan_fixtures import PAYORS, database_state, plan
from database.tests.test_value_codes_display import (
    KEYS, NONE, RECIPES, configure_source, current, cursor, display,
)

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_VALUE_CODES_CONTROLS") != "1",
    reason="Set RUN_ORACLE_VALUE_CODES_CONTROLS=1 for local rollback-only control tests",
)

OMITTED = object()
NEUTRAL = {"012": "GET_VAL_CODE", "015": "GET_VAL_CODE_AMT",
           "022": "GET_VAL_CODE", "025": "GET_VAL_CODE_AMT"}
AUDITS = {"rec_ent_date", "rec_ent_user", "rec_mod_date", "rec_mod_user"}


def request(cursor, owner=0, number=0, selections=NONE, behavior=OMITTED, expected_hash=None):
    before = fingerprint(database_state(cursor))
    with cursor.connection.cursor() as summary, cursor.connection.cursor() as changes:
        args = [PAYORS[owner], plan(owner, number) if number else None,
                *("Y" if selections[key] else "N" for key in KEYS), "SYN_VALUE_CONTROLS_TEST"]
        operation = "preview" if expected_hash is None else "apply"
        if expected_hash is not None:
            args.append(expected_hash)
        args += [summary, changes]
        if behavior is not OMITTED:
            args.append(behavior)
        try:
            cursor.callproc(f"pfc_value_codes_api.{operation}_configuration", args)
            row = dict(zip((column[0].lower() for column in summary.description), summary.fetchone()))
            changed = changes.fetchall()
            return row, changed
        finally:
            if operation == "preview":
                assert fingerprint(database_state(cursor)) == before, "Preview must not mutate configuration"


def apply(cursor, **kwargs):
    preview, _ = request(cursor, **kwargs)
    result, _ = request(cursor, expected_hash=preview["state_hash"], **kwargs)
    return preview, result


def record(cursor, guid):
    cursor.execute("SELECT * FROM hcfa_electronic_records WHERE electronic_rec_guid=:guid", guid=guid)
    return dict(zip((column[0].lower() for column in cursor.description), cursor.fetchone()))


def fields(cursor, guid):
    cursor.execute("SELECT * FROM hcfa_electronic_fields WHERE electronic_rec_guid=:guid", guid=guid)
    columns = [column[0].lower() for column in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def override_guid(cursor, owner, number):
    cursor.execute("""SELECT electronic_rec_guid FROM hcfa_electronic_records WHERE payor_guid=:payor
        AND (plan_guid=:plan OR (plan_guid IS NULL AND :plan IS NULL))
        AND record_type_code='D23002310HI286' AND billing_form_code='837I_5010'""",
                   payor=PAYORS[owner], plan=plan(owner, number) if number else None)
    found = cursor.fetchall()
    assert len(found) == 1
    return found[0][0]


def make_neutral_source(cursor, source):
    for number, procedure in NEUTRAL.items():
        cursor.execute("""UPDATE hcfa_electronic_fields SET sto_proc_name=:procedure, hard_coded_data=NULL
            WHERE electronic_rec_guid=:source AND field_number=:field_number""",
                       procedure=procedure, source=source, field_number=number)
        assert cursor.rowcount == 1


def without_audits(row):
    return {key: value for key, value in row.items() if key not in AUDITS | {"electronic_rec_guid"}}


@pytest.mark.parametrize("number", [0, 1])
def test_home_health_off_preserves_generic_patient_values_source_gate_and_all_other_content(cursor, number):
    source, _ = configure_source(cursor, "fips")
    source_her, source_hefs = record(cursor, source), fields(cursor, source)
    before = database_state(cursor)
    preview, result = apply(cursor, number=number, behavior="OFF")
    assert preview["target_action"] == "REBUILD_OVERRIDE" and result["status"] == "APPLIED"
    guid = override_guid(cursor, 0, number)
    actual = record(cursor, guid)
    cursor.execute("SELECT payor_type_guid FROM payors WHERE payor_guid=:payor", payor=PAYORS[0])
    expected = {**source_her, "payor_guid": PAYORS[0], "plan_guid": plan(0, number) if number else None,
                "payor_type_guid": cursor.fetchone()[0],
                "carry_forward_ind": None, "include_record_data_onclaim": "Y"}
    assert without_audits(actual) == without_audits(expected)
    assert actual["sto_proc_name"] == "RETURN_1", "CBSA/FIPS off must not suppress other Value Codes"
    expected_fields = [{**field, **({"sto_proc_name": NEUTRAL[field["field_number"]], "hard_coded_data": None}
                                   if field["field_number"] in NEUTRAL else {})} for field in source_hefs]
    assert fingerprint({"fields": [without_audits(field) for field in fields(cursor, guid)]}) == fingerprint({
        "fields": [without_audits(field) for field in expected_fields]})
    # Only the new selected-scope override and its complete children were added.
    after = database_state(cursor)
    after["HCFA_ELECTRONIC_RECORDS"] = [row for row in after["HCFA_ELECTRONIC_RECORDS"] if row["electronic_rec_guid"] != guid]
    after["HCFA_ELECTRONIC_FIELDS"] = [row for row in after["HCFA_ELECTRONIC_FIELDS"] if row["electronic_rec_guid"] != guid]
    assert fingerprint(after) == fingerprint(before)
    resolved = current(cursor, 0, number)
    assert resolved["is_default"] == "N" and resolved["canonical_status"] == "CANONICAL_OVERRIDE"
    assert display(resolved, "effective_selections") == NONE
    assert all(resolved[key] == "N" for key in KEYS)


@pytest.mark.parametrize("neutral", [False, True])
def test_home_health_off_never_enables_a_disabled_parent(cursor, neutral):
    source, _ = configure_source(cursor, "fips")
    cursor.execute("UPDATE hcfa_electronic_records SET sto_proc_name='RETURN_0' WHERE electronic_rec_guid=:source", source=source)
    if neutral:
        make_neutral_source(cursor, source)
    preview, _ = apply(cursor, behavior="OFF")
    assert preview["target_action"] == ("NO_CHANGE" if neutral else "REBUILD_OVERRIDE")
    row = current(cursor)
    assert display(row, "effective_selections") == NONE
    assert record(cursor, source if neutral else override_guid(cursor, 0, 0))["sto_proc_name"] == "RETURN_0"
    assert row["is_default"] == ("Y" if neutral else "N")


@pytest.mark.parametrize("recipe", ["cbsa", "fips"])
def test_home_health_roundtrip_removes_override_when_selection_matches_parent(cursor, recipe):
    _, inherited = configure_source(cursor, recipe)
    apply(cursor, number=1, behavior="OFF")
    preview, _ = apply(cursor, number=1, selections=inherited, behavior="OFF")
    assert preview["target_action"] == "REMOVE_OVERRIDE"
    assert current(cursor, 0, 1)["is_default"] == "Y"
    assert display(current(cursor, 0, 1), "effective_selections") == inherited
    apply(cursor, number=1, behavior="OFF")
    legacy, _ = apply(cursor, number=1)
    assert legacy["target_action"] == "REMOVE_OVERRIDE"
    assert display(current(cursor, 0, 1), "effective_selections") == inherited


def test_plan_off_inherits_neutral_payor_without_touching_parent_or_siblings(cursor):
    configure_source(cursor, "cbsa")
    apply(cursor, behavior="OFF")
    parent = record(cursor, override_guid(cursor, 0, 0))
    sibling = current(cursor, 0, 2)
    assert display(current(cursor, 0, 1), "effective_selections") == NONE
    apply(cursor, number=1, selections=dict(zip(KEYS, RECIPES["fips"][1])), behavior="OFF")
    preview, _ = apply(cursor, number=1, behavior="OFF")
    assert preview["target_action"] == "REMOVE_OVERRIDE"
    assert current(cursor, 0, 1)["is_default"] == "Y"
    assert record(cursor, parent["electronic_rec_guid"]) == parent
    assert current(cursor, 0, 2) == sibling


@pytest.mark.parametrize("number", [0, 1])
def test_hospice_off_suppresses_record_and_preserves_complete_source_hefs(cursor, number):
    source, inherited = configure_source(cursor, "care_days")
    source_fields = fields(cursor, source)
    preview, _ = apply(cursor, owner=1, number=number, behavior="OFF")
    assert preview["target_action"] == "REBUILD_OVERRIDE"
    guid = override_guid(cursor, 1, number)
    her = record(cursor, guid)
    assert her["sto_proc_name"] == "RETURN_0" and her["mandatory_ind"] == "N"
    assert fingerprint({"fields": [without_audits(field) for field in fields(cursor, guid)]}) == fingerprint({
        "fields": [without_audits(field) for field in source_fields]})
    resolved = current(cursor, 1, number)
    assert resolved["is_default"] == "N" and display(resolved, "effective_selections") == NONE
    preview, _ = apply(cursor, owner=1, number=number, selections=inherited, behavior="OFF")
    assert preview["target_action"] == "REMOVE_OVERRIDE"


@pytest.mark.parametrize("gate", ["RETURN_1", "RETURN_0"])
def test_complete_known_inherited_home_health_neutral_is_displayed_as_both_off(cursor, gate):
    source, _ = configure_source(cursor, "cbsa")
    make_neutral_source(cursor, source)
    cursor.execute("UPDATE hcfa_electronic_records SET sto_proc_name=:gate WHERE electronic_rec_guid=:source", gate=gate, source=source)
    row = current(cursor)
    assert row["is_default"] == "Y" and display(row, "effective_selections") == NONE
    assert display(row, "inherited_selections") == NONE


@pytest.mark.parametrize("gate", [None, "SYN_CONDITIONAL_VALUE_CODES"])
def test_unknown_inherited_gate_stays_unknown_but_explicit_neutral_retains_it(cursor, gate):
    source, _ = configure_source(cursor, "fips")
    cursor.execute("UPDATE hcfa_electronic_records SET sto_proc_name=:gate WHERE electronic_rec_guid=:source", gate=gate, source=source)
    assert display(current(cursor), "effective_selections") is None
    apply(cursor, behavior="OFF")
    row = current(cursor)
    assert row["is_default"] == "N" and display(row, "effective_selections") == NONE
    assert display(row, "inherited_selections") is None
    assert record(cursor, override_guid(cursor, 0, 0))["sto_proc_name"] == gate
    # An inherited neutral-shaped record with unknown gating is still not inferred.
    apply(cursor)
    make_neutral_source(cursor, source)
    assert display(current(cursor), "effective_selections") is None


@pytest.mark.parametrize("gate", [None, "SYN_CONDITIONAL_VALUE_CODES"])
@pytest.mark.parametrize("number", [0, 2])
def test_explicit_off_cannot_collapse_to_unrecognized_neutral_inheritance(cursor, gate, number):
    source, _ = configure_source(cursor, "cbsa")
    make_neutral_source(cursor, source)
    cursor.execute("UPDATE hcfa_electronic_records SET sto_proc_name=:gate WHERE electronic_rec_guid=:source", gate=gate, source=source)
    old, _ = request(cursor, number=number)
    assert old["target_action"] == ("NO_CHANGE" if number == 0 else "REMOVE_OVERRIDE")
    before = fingerprint(database_state(cursor))
    for expected in (None, old["state_hash"]):
        with pytest.raises(oracledb.DatabaseError, match="ORA-20063"):
            request(cursor, number=number, behavior="OFF", expected_hash=expected)
        assert fingerprint(database_state(cursor)) == before


@pytest.mark.parametrize("defect", ["missing-procedure", "wrong-field-name", "duplicate-field"])
def test_inherited_neutral_recognition_requires_complete_managed_fields(cursor, defect):
    source, _ = configure_source(cursor, "cbsa")
    make_neutral_source(cursor, source)
    if defect == "missing-procedure":
        cursor.execute("""UPDATE hcfa_electronic_fields SET sto_proc_name=NULL
            WHERE electronic_rec_guid=:source AND field_number='012'""", source=source)
    elif defect == "wrong-field-name":
        cursor.execute("""UPDATE hcfa_electronic_fields SET field_name='SYN_NOT_HI012'
            WHERE electronic_rec_guid=:source AND field_number='012'""", source=source)
    else:
        from database.maintenance.rebuild_hierarchy import insert_rows
        duplicate = next(field for field in fields(cursor, source) if field["field_number"] == "012")
        insert_rows(cursor, "HCFA_ELECTRONIC_FIELDS", [duplicate])
    assert display(current(cursor), "effective_selections") is None


@pytest.mark.parametrize("recipe", RECIPES)
def test_nonempty_requests_keep_exact_legacy_code_hash_and_preview(cursor, recipe):
    owner, flags, _ = RECIPES[recipe]
    selections = dict(zip(KEYS, flags))
    old = request(cursor, owner=owner, selections=selections)
    assert request(cursor, owner=owner, selections=selections, behavior="INHERIT") == old
    assert request(cursor, owner=owner, selections=selections, behavior="OFF") == old
    assert old[0]["option_code"] == "VC|" + ("HOME_HEALTH" if owner == 0 else "HOSPICE") + "|" + "|".join("Y" if flag else "N" for flag in flags)


@pytest.mark.parametrize("owner", [0, 1])
@pytest.mark.parametrize("preview_behavior,apply_behavior", [("INHERIT", "OFF"), ("OFF", "INHERIT")])
def test_legacy_default_and_explicit_off_hashes_cannot_be_interchanged(cursor, owner, preview_behavior, apply_behavior):
    old = request(cursor, owner=owner)
    assert request(cursor, owner=owner, behavior="INHERIT") == old
    off = request(cursor, owner=owner, behavior="OFF")
    assert off[0]["option_code"] == old[0]["option_code"] + "|OFF"
    assert off[0]["state_hash"] != old[0]["state_hash"]
    preview, _ = request(cursor, owner=owner, behavior=preview_behavior)
    before = fingerprint(database_state(cursor))
    with pytest.raises(oracledb.DatabaseError, match="ORA-20036"):
        request(cursor, owner=owner, behavior=apply_behavior, expected_hash=preview["state_hash"])
    assert fingerprint(database_state(cursor)) == before


@pytest.mark.parametrize("behavior", [None, "", " ", "DEFAULT", "OFFX", "X" * 150])
@pytest.mark.parametrize("operation", ["preview", "apply"])
def test_invalid_empty_selection_behavior_fails_before_mutation(cursor, behavior, operation):
    old, _ = request(cursor)
    before = fingerprint(database_state(cursor))
    with pytest.raises(oracledb.DatabaseError, match="ORA-20062"):
        request(cursor, behavior=behavior, expected_hash=old["state_hash"] if operation == "apply" else None)
    assert fingerprint(database_state(cursor)) == before


def test_empty_behavior_normalizes_case_and_surrounding_spaces(cursor):
    assert request(cursor, behavior=" off ") == request(cursor, behavior="OFF")
    assert request(cursor, behavior=" inherit ") == request(cursor)
