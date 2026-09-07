"""Effective Value Codes display metadata; synthetic changes always roll back."""

import json
import os
from pathlib import Path
from uuid import uuid4

import oracledb
import pytest

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.rebuild_hierarchy import fingerprint, insert_rows, procedure_row
from database.maintenance.seed_payor_plans import structured_apply
from database.tests.plan_fixtures import PAYORS, database_state, plan, seed


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_VALUE_CODES_DISPLAY") != "1",
    reason="Set RUN_ORACLE_VALUE_CODES_DISPLAY=1 for local rollback-only display tests",
)

KEYS = ("cbsa", "fips", "care_location_value_code", "patient_entered_value_code", "covered_days_value_code")
OLD_COLUMNS = ("configuration_status", "line_of_business", "is_default", *KEYS,
               "canonical_status", "display_summary", "pfc_guid", "billing_form_code",
               "source_electronic_rec_guid", "existing_payor_her_count",
               "existing_payor_hef_count", "state_hash", "configuration_owners")
RECORD_TYPE = "D23002310HI286"
RECIPES = {
    "cbsa": (0, (True, False, False, False, False),
             ((None, "61"), ("GET_PAT_CBSA_CODE", None), ("GET_VAL_CODE", None), ("GET_VAL_CODE_AMT", None))),
    "fips": (0, (True, True, False, False, False),
             ((None, "61"), ("GET_PAT_CBSA_CODE", None), ("GET_FIPS_CODE", None), ("GET_FIPS_CODE_VALUE", None))),
    "care": (1, (False, False, True, False, False),
             (("GET_CARE_LOC_CODE", None), ("GET_CARE_LOC_VAL_CODE", None), ("GET_VAL_CODE", None), ("GET_VAL_CODE_AMT", None))),
    "care_days": (1, (False, False, True, False, True),
                  (("GET_CARE_LOC_CODE", None), ("GET_CARE_LOC_VAL_CODE", None), (None, "80"), ("GET_DISTINCT_COVERED_DAYS", None))),
    "patient": (1, (False, False, False, True, False),
                (("GET_VAL_CODE", None), ("GET_VAL_CODE_AMT", None), ("GET_VAL_CODE", None), ("GET_VAL_CODE_AMT", None))),
    "patient_days": (1, (False, False, False, True, True),
                     (("GET_VAL_CODE", None), ("GET_VAL_CODE_AMT", None), (None, "80"), ("GET_DISTINCT_COVERED_DAYS", None))),
    "days": (1, (False, False, False, False, True),
             ((None, "80"), ("GET_DISTINCT_COVERED_DAYS", None), ("GET_VAL_CODE", None), ("GET_VAL_CODE_AMT", None))),
}
NONE = dict.fromkeys(KEYS, False)


@pytest.fixture
def cursor():
    assert get_oracle_settings().host.lower() in {"localhost", "127.0.0.1", "::1"}, "Local synthetic tests only"
    with create_connection() as connection:
        with connection.cursor() as cursor:
            before = fingerprint(database_state(cursor))
            try:
                seed(cursor)
                yield cursor
            finally:
                connection.rollback()
                assert fingerprint(database_state(cursor)) == before, "All configuration and plan ownership must be restored"


def current(cursor, owner=0, number=0):
    before = fingerprint(database_state(cursor))
    try:
        return procedure_row(cursor, "pfc_value_codes_api.current_configuration",
                             [PAYORS[owner], plan(owner, number) if number else None])
    finally:
        assert fingerprint(database_state(cursor)) == before, "Current must remain read-only"


def display(row, column):
    raw = row[column]
    if raw is None:
        return None
    result = json.loads(raw)
    assert set(result) == set(KEYS)
    assert all(type(value) is bool for value in result.values())
    return result


def configure_source(cursor, recipe):
    owner, flags, fields = RECIPES[recipe]
    source = current(cursor, owner)["source_electronic_rec_guid"]
    cursor.execute("""UPDATE hcfa_electronic_records SET sto_proc_name='RETURN_1', mandatory_ind='N'
        WHERE electronic_rec_guid=:source""", source=source)
    for number, (procedure, literal) in zip(("012", "015", "022", "025"), fields):
        cursor.execute("""UPDATE hcfa_electronic_fields SET sto_proc_name=:procedure, hard_coded_data=:literal
            WHERE electronic_rec_guid=:source AND field_number=:field_number""",
                       procedure=procedure, literal=literal, source=source, field_number=number)
        assert cursor.rowcount == 1
    return source, dict(zip(KEYS, flags))


def apply_selection(cursor, owner, number, flags):
    return structured_apply(cursor, "pfc_value_codes_api", [PAYORS[owner],
        plan(owner, number) if number else None, *("Y" if flags[key] else "N" for key in KEYS)])


def preview_selection(cursor, owner, number, flags):
    with cursor.connection.cursor() as summary, cursor.connection.cursor() as changes:
        cursor.callproc("pfc_value_codes_api.preview_configuration", [PAYORS[owner],
            plan(owner, number) if number else None, *("Y" if flags[key] else "N" for key in KEYS),
            "SYN_VALUE_DISPLAY_TEST", summary, changes])
        return dict(zip((column[0].lower() for column in summary.description), summary.fetchone()))


@pytest.mark.parametrize("recipe", RECIPES)
@pytest.mark.parametrize("number", [0, 1])
def test_each_inherited_recipe_has_effective_flags_without_changing_default_intent(cursor, recipe, number):
    owner = RECIPES[recipe][0]
    source, expected = configure_source(cursor, recipe)
    row = current(cursor, owner, number)
    assert tuple(row) == (*OLD_COLUMNS, "effective_selections", "inherited_selections")
    assert row["configuration_status"] == "RESOLVED"
    assert row["is_default"] == "Y" and row["canonical_status"] == "INHERITED"
    assert all(row[key] == "N" for key in KEYS), "Original edit-intent columns must remain Default"
    assert row["source_electronic_rec_guid"] == source
    assert row["existing_payor_her_count"] == 0
    assert display(row, "effective_selections") == expected
    assert display(row, "inherited_selections") == expected


@pytest.mark.parametrize("owner,recipe", [(0, "fips"), (1, "care_days")])
def test_user_template_capabilities_are_machine_readable(cursor, owner, recipe):
    original = json.loads((Path(__file__).resolve().parents[1] / "maintenance" / "hierarchy_seed.json").read_text())
    marker = "GET_FIPS_CODE" if owner == 0 else "GET_DISTINCT_COVERED_DAYS"
    source = next(row for row in original["HCFA_ELECTRONIC_RECORDS"]
                  if row["user_form_template_guid"] and row["record_type_code"] == RECORD_TYPE
                  and any(field["electronic_rec_guid"] == row["electronic_rec_guid"]
                          and field["sto_proc_name"] == marker for field in original["HCFA_ELECTRONIC_FIELDS"]))
    cursor.execute("UPDATE pfc SET user_form_template_guid=:template WHERE payor_guid=:payor",
                   template=source["user_form_template_guid"], payor=PAYORS[owner])
    configure_source(cursor, recipe)
    row = current(cursor, owner)
    assert json.loads(row["configuration_owners"])[0]["level"] == "USER_TEMPLATE"
    assert display(row, "effective_selections") == dict(zip(KEYS, RECIPES[recipe][1]))
    assert display(row, "inherited_selections") == display(row, "effective_selections")
    assert row["is_default"] == "Y" and all(row[key] == "N" for key in KEYS)


@pytest.mark.parametrize("owner,base,explicit", [(0, "cbsa", "fips"), (1, "care", "patient_days")])
def test_explicit_plan_keeps_effective_and_parent_capabilities_separate(cursor, owner, base, explicit):
    configure_source(cursor, base)
    row = current(cursor, owner, 2)
    expected = dict(zip(KEYS, RECIPES[explicit][1]))
    assert row["is_default"] == "N" and row["canonical_status"] == "CANONICAL_OVERRIDE"
    assert display(row, "effective_selections") == expected
    assert {key: row[key] == "Y" for key in KEYS} == expected
    assert display(row, "inherited_selections") == dict(zip(KEYS, RECIPES[base][1]))


def test_plan_inherits_its_payor_and_redundant_override_keeps_default_intent(cursor):
    configure_source(cursor, "cbsa")
    wanted = dict(zip(KEYS, RECIPES["fips"][1]))
    apply_selection(cursor, 0, 0, wanted)
    inherited = current(cursor, 0, 1)
    assert json.loads(inherited["configuration_owners"])[0]["level"] == "PAYOR"
    assert display(inherited, "effective_selections") == wanted
    assert display(inherited, "inherited_selections") == wanted
    redundant = current(cursor, 0, 2)
    assert redundant["canonical_status"] == "REDUNDANT_OVERRIDE"
    assert redundant["is_default"] == "Y" and all(redundant[key] == "N" for key in KEYS)
    assert display(redundant, "effective_selections") == wanted
    assert display(redundant, "inherited_selections") == wanted


@pytest.mark.parametrize("procedure,expected", [("RETURN_0", NONE), ("SYN_CONDITIONAL_VALUE_CODES", None), (None, None)])
def test_off_and_unrecognized_inheritance_are_distinct(cursor, procedure, expected):
    source, _ = configure_source(cursor, "cbsa")
    cursor.execute("UPDATE hcfa_electronic_records SET sto_proc_name=:procedure WHERE electronic_rec_guid=:source",
                   procedure=procedure, source=source)
    inherited = current(cursor)
    assert display(inherited, "effective_selections") == expected
    assert display(inherited, "inherited_selections") == expected
    assert inherited["is_default"] == "Y" and all(inherited[key] == "N" for key in KEYS)
    # A supported explicit override can coexist with an unrecognized parent.
    explicit = current(cursor, 0, 2)
    assert display(explicit, "effective_selections") == dict(zip(KEYS, RECIPES["fips"][1]))
    assert display(explicit, "inherited_selections") == expected


def test_unsafe_off_source_remains_blocked(cursor):
    source, _ = configure_source(cursor, "cbsa")
    cursor.execute("""UPDATE hcfa_electronic_records SET sto_proc_name='RETURN_0', mandatory_ind='Y'
        WHERE electronic_rec_guid=:source""", source=source)
    with pytest.raises(oracledb.DatabaseError, match="ORA-20012"):
        current(cursor)


@pytest.mark.parametrize("recipe,field_number", [
    ("cbsa", "015"), ("cbsa", "012"), ("fips", "022"),
    ("care_days", "022"), ("patient", "012"), ("days", "012"),
])
def test_missing_required_hef_value_cannot_be_recognized_as_enabled(cursor, recipe, field_number):
    source, _ = configure_source(cursor, recipe)
    cursor.execute("""UPDATE hcfa_electronic_fields SET sto_proc_name=NULL, hard_coded_data=NULL
        WHERE electronic_rec_guid=:source AND field_number=:field_number""",
                   source=source, field_number=field_number)
    row = current(cursor, RECIPES[recipe][0])
    assert row["configuration_status"] == "RESOLVED" and row["is_default"] == "Y"
    assert display(row, "effective_selections") is None
    assert display(row, "inherited_selections") is None


@pytest.mark.parametrize("field_number,procedure,literal", [
    ("012", "SYN_UNRECOGNIZED_VALUE", None),
    ("015", None, "SYN_UNRECOGNIZED_VALUE"),
])
def test_wrong_member_of_a_managed_value_pair_cannot_match_a_recipe(cursor, field_number, procedure, literal):
    source, _ = configure_source(cursor, "cbsa")
    cursor.execute("""UPDATE hcfa_electronic_fields SET sto_proc_name=:procedure, hard_coded_data=:literal
        WHERE electronic_rec_guid=:source AND field_number=:field_number""",
                   source=source, field_number=field_number, procedure=procedure, literal=literal)
    row = current(cursor)
    assert display(row, "effective_selections") is None
    assert display(row, "inherited_selections") is None


def test_state_comparison_distinguishes_missing_her_procedure_from_return_one(cursor):
    result = cursor.var(int)
    cursor.execute("""DECLARE
        l_missing pfc_value_codes.t_configuration_state;
        l_enabled pfc_value_codes.t_configuration_state;
    BEGIN
        l_enabled.her_sto_proc_name := 'RETURN_1';
        :result := pfc_value_codes.canonical_override_count(l_missing, l_enabled)
            + pfc_value_codes.canonical_override_count(l_enabled, l_missing)
            + pfc_value_codes.canonical_override_count(l_missing, l_missing);
    END;""", result=result)
    assert result.getvalue() == 2, "One missing procedure is unequal; two missing procedures are equal"


@pytest.mark.parametrize("mode", ["default", "explicit-equal", "already-inherited"])
def test_default_and_minimal_override_apply_keep_inherited_effective_flags(cursor, mode):
    _, inherited = configure_source(cursor, "cbsa")
    number = 1 if mode == "already-inherited" else 2
    sibling_before = current(cursor, 0, 3)
    requested = NONE if mode == "default" else inherited
    preview = preview_selection(cursor, 0, number, requested)
    assert preview["target_action"] == ("NO_CHANGE" if mode == "already-inherited" else "REMOVE_OVERRIDE")
    result = apply_selection(cursor, 0, number, requested)
    assert result["status"] == ("NO_CHANGE" if mode == "already-inherited" else "APPLIED")
    row = current(cursor, 0, number)
    assert row["is_default"] == "Y" and row["existing_payor_her_count"] == 0
    assert all(row[key] == "N" for key in KEYS)
    assert display(row, "effective_selections") == inherited
    assert display(row, "inherited_selections") == inherited
    assert current(cursor, 0, 3) == sibling_before


def test_duplicate_current_remains_blocked_without_guessing_effective_capabilities(cursor):
    configure_source(cursor, "cbsa")
    cursor.execute("""SELECT * FROM hcfa_electronic_records WHERE payor_guid=:payor
        AND plan_guid=:plan AND record_type_code=:record_type""", payor=PAYORS[0],
                   plan=plan(0, 2), record_type=RECORD_TYPE)
    row = dict(zip((column[0].lower() for column in cursor.description), cursor.fetchone()))
    original = row["electronic_rec_guid"]
    row["electronic_rec_guid"] = str(uuid4()).upper()
    insert_rows(cursor, "HCFA_ELECTRONIC_RECORDS", [row])
    cursor.execute("SELECT * FROM hcfa_electronic_fields WHERE electronic_rec_guid=:source", source=original)
    columns = [column[0].lower() for column in cursor.description]
    fields = [dict(zip(columns, values)) for values in cursor.fetchall()]
    insert_rows(cursor, "HCFA_ELECTRONIC_FIELDS", [{**field, "electronic_rec_guid": row["electronic_rec_guid"]} for field in fields])
    blocked = current(cursor, 0, 2)
    assert blocked["configuration_status"] == "BLOCKED_DUPLICATE_PAYOR_HER"
    assert display(blocked, "effective_selections") is None
    assert display(blocked, "inherited_selections") == dict(zip(KEYS, RECIPES["cbsa"][1]))
