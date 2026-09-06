"""Rollback-only integration checks with isolated transaction-local plan fixtures."""
import json
import os

import oracledb
import pytest

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.rebuild_hierarchy import procedure_row, fingerprint
from database.maintenance.seed_payor_plans import change, apply_option, structured_apply
from database.tests.plan_fixtures import PAYORS, plan, pfc, seed, database_state

pytestmark = pytest.mark.skipif(os.getenv("RUN_ORACLE_PLANS") != "1", reason="Set RUN_ORACLE_PLANS=1 for local plan integration")

@pytest.fixture
def rollback_cursor():
    assert get_oracle_settings().host.lower() in {"localhost", "127.0.0.1", "::1"}, "Local synthetic plan tests only"
    with create_connection() as connection:
        with connection.cursor() as cursor:
            before = fingerprint(database_state(cursor))
            try:
                yield cursor
            finally:
                connection.rollback()
                assert fingerprint(database_state(cursor)) == before


@pytest.fixture
def cursor(rollback_cursor):
    seed(rollback_cursor)
    return rollback_cursor

def current(cursor, owner=0, number=1, field="81"):
    return procedure_row(cursor, "pfc_get_current_config", [PAYORS[owner], plan(owner, number) if number else None, field])

def test_seeded_current_states_and_newest_entry_date(cursor):
    for owner, payor in enumerate(PAYORS):
        for number in range(4):
            selected = plan(owner, number) if number else None
            row = current(cursor, owner=owner, number=number)
            assert row["effective_option_code"] == ("PROVIDER_TAXONOMY_OFF" if number == 2 else "PROVIDER_TAXONOMY_ON")
            assert row["pfc_guid"] == pfc(owner, number)
            for package in ("pfc_value_codes_api", "pfc_remarks_api"):
                row = procedure_row(cursor, package + ".current_configuration", [payor, selected])
                assert row["configuration_status"] == "RESOLVED", row
    assert json.loads(current(cursor)["configuration_owners"])[0]["level"] == "PAYOR"
    assert json.loads(current(cursor, number=2)["configuration_owners"])[0]["level"] == "PAYOR_PLAN"

def test_default_removes_only_exact_plan_and_inherits_parent(cursor):
    result = change(cursor, PAYORS[0], plan(0, 2), "PROVIDER_TAXONOMY_ON")
    assert result["target_action"] == "REMOVE_OVERRIDE"
    apply_option(cursor, PAYORS[0], plan(0, 2), "PROVIDER_TAXONOMY_ON")
    assert current(cursor, number=2)["effective_option_code"] == "PROVIDER_TAXONOMY_ON"
    assert current(cursor, number=0)["effective_option_code"] == "PROVIDER_TAXONOMY_ON"
    assert current(cursor, number=3)["effective_option_code"] == "PROVIDER_TAXONOMY_ON"

def test_parent_change_preserves_exact_plan_and_invalidates_preview(cursor):
    preview = change(cursor, PAYORS[0], plan(0, 1), "PROVIDER_TAXONOMY_OFF")
    apply_option(cursor, PAYORS[0], None, "PROVIDER_TAXONOMY_OFF")
    with pytest.raises(oracledb.DatabaseError, match="2004[0-9]|stale|changed"):
        change(cursor, PAYORS[0], plan(0, 1), "PROVIDER_TAXONOMY_OFF", "APPLY", preview["state_hash"])
    assert current(cursor, number=2)["effective_option_code"] == "PROVIDER_TAXONOMY_OFF"

def test_plan_owner_mismatch_and_reassignment_are_rejected(cursor):
    with pytest.raises(oracledb.DatabaseError, match="20010"):
        procedure_row(cursor, "pfc_get_current_config", [PAYORS[1], plan(0, 1), "81"])
    with pytest.raises(oracledb.DatabaseError, match="20010"):
        cursor.execute("UPDATE pfc SET payor_guid=:p WHERE plan_guid=:g", p=PAYORS[1], g=plan(0, 1))
    with pytest.raises(oracledb.DatabaseError, match="20010"):
        cursor.execute("UPDATE pfc_config_plans SET payor_guid=:p WHERE plan_guid=:g", p=PAYORS[1], g=plan(0, 1))

def test_tied_pfc_dates_block_and_new_winner_invalidates_preview(cursor):
    preview = change(cursor, PAYORS[0], plan(0, 2), "PROVIDER_TAXONOMY_ON")
    cursor.execute("UPDATE pfc SET rec_ent_date=DATE '2026-09-01' WHERE payor_guid=:p AND plan_guid=:g", p=PAYORS[0], g=plan(0, 2))
    with pytest.raises(oracledb.DatabaseError, match="20011"):
        current(cursor, number=2)
    cursor.execute("UPDATE pfc SET rec_ent_date=DATE '2026-09-02' WHERE pfc_guid=:g", g=pfc(0, 99))
    with pytest.raises(oracledb.DatabaseError, match="2004[0-9]|stale|changed"):
        change(cursor, PAYORS[0], plan(0, 2), "PROVIDER_TAXONOMY_ON", "APPLY", preview["state_hash"])

def test_multirecord_and_structured_default_preserve_other_levels(cursor):
    before = current(cursor, number=3, field="77")
    apply_option(cursor, PAYORS[0], plan(0, 2), "SERVICE_FACILITY_NEVER")
    assert current(cursor, number=3, field="77") == before
    for owner in range(2):
        structured_apply(cursor, "pfc_remarks_api", [PAYORS[owner], plan(owner, 2), "DEFAULT", None])
        structured_apply(cursor, "pfc_value_codes_api", [PAYORS[owner], plan(owner, 2), "N", "N", "N", "N", "N"])
        for package in ("pfc_remarks_api", "pfc_value_codes_api"):
            result = procedure_row(cursor, package+".current_configuration", [PAYORS[owner], plan(owner, 2)])
            assert result["canonical_status"] == "INHERITED"

def test_unchanged_plan_option_is_no_change(cursor):
    result = change(cursor, PAYORS[0], plan(0, 2), "PROVIDER_TAXONOMY_OFF")
    assert result["target_action"] == "NO_CHANGE"

def test_missing_pfc_entry_date_is_rejected_by_storage(cursor):
    with pytest.raises(oracledb.DatabaseError, match="01407"):
        cursor.execute("UPDATE pfc SET rec_ent_date=NULL WHERE payor_guid=:p AND plan_guid=:g", p=PAYORS[0], g=plan(0, 1))

def test_complete_hef_clone_preserves_unmanaged_fields(cursor):
    cursor.execute("SELECT electronic_rec_guid FROM hcfa_electronic_records WHERE payor_guid=:p AND plan_guid IS NULL AND record_type_code='B2000A0030PRV080'", p=PAYORS[0])
    parent = cursor.fetchone()[0]
    apply_option(cursor, PAYORS[0], plan(0, 1), "PROVIDER_TAXONOMY_OFF")
    cursor.execute("SELECT electronic_rec_guid FROM hcfa_electronic_records WHERE payor_guid=:p AND plan_guid=:g AND record_type_code='B2000A0030PRV080'", p=PAYORS[0], g=plan(0, 1))
    child = cursor.fetchone()[0]
    def fields(guid):
        cursor.execute("SELECT * FROM hcfa_electronic_fields WHERE electronic_rec_guid=:g", g=guid)
        names = [d[0].lower() for d in cursor.description]
        return sorted([tuple((k,v) for k,v in zip(names,row) if k not in {'electronic_rec_guid','rec_ent_date','rec_ent_user','rec_mod_date','rec_mod_user'}) for row in cursor], key=repr)
    assert fields(parent) == fields(child)

def test_plan_inherits_parent_remarks_without_copying_or_removing_parent(cursor):
    structured_apply(cursor, "pfc_remarks_api", [PAYORS[0], None, "CUSTOM", "Synthetic parent remark"])
    row = procedure_row(cursor, "pfc_remarks_api.current_configuration", [PAYORS[0], plan(0, 1)])
    assert row["canonical_status"] == "INHERITED"
    assert json.loads(row["configuration_owners"])[0]["level"] == "PAYOR"
    structured_apply(cursor, "pfc_remarks_api", [PAYORS[0], plan(0, 2), "DEFAULT", None])
    parent = procedure_row(cursor, "pfc_remarks_api.current_configuration", [PAYORS[0], None])
    assert parent["custom_remark"] == "Synthetic parent remark"

def test_pfc_edits_wait_for_configuration_payor_lock(rollback_cursor):
    from concurrent.futures import ThreadPoolExecutor, TimeoutError
    from threading import Event
    cursor = rollback_cursor
    ready = Event()
    # The writer needs a committed PFC visible in its own session. This test only
    # locks an existing synthetic payor, temporarily updates its PFC, and rolls
    # back both sessions; no expected configuration depends on demo content.
    cursor.execute("""
        SELECT p.payor_guid, p.pfc_guid FROM pfc p
        JOIN payors owner ON owner.payor_guid = p.payor_guid
        WHERE owner.payor_id LIKE 'SYN-%' AND owner.payor_guid NOT LIKE 'D1000000-%'
        ORDER BY p.payor_guid, p.pfc_guid FETCH FIRST 1 ROW ONLY
    """)
    target = cursor.fetchone()
    assert target is not None, "A committed synthetic PFC is required for the two-session lock check"
    payor_guid, pfc_guid = target
    cursor.execute("SELECT payor_guid FROM payors WHERE payor_guid=:p FOR UPDATE", p=payor_guid)
    def write():
        with create_connection() as other:
            try:
                with other.cursor() as writer:
                    ready.set()
                    writer.execute("UPDATE pfc SET rec_ent_date=SYSDATE WHERE pfc_guid=:g", g=pfc_guid)
                    assert writer.rowcount == 1
            finally:
                other.rollback()
    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(write)
        try:
            assert ready.wait(5)
            with pytest.raises(TimeoutError):
                future.result(timeout=0.2)
        finally:
            cursor.connection.rollback()
        future.result(timeout=5)
