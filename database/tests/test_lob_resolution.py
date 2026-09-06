"""Rollback-only checks for the shared saved Line of Business reader."""

import json
import os
from pathlib import Path

import oracledb
import pytest

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.rebuild_hierarchy import fingerprint, insert_rows, read_state


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_LOB_RESOLUTION") != "1",
    reason="Set RUN_ORACLE_LOB_RESOLUTION=1 for local saved-LOB integration checks",
)

PAYORS = tuple(f"E4000000-0000-0000-0000-{number:012d}" for number in range(1, 4))
MISSING_PAYOR = "E4000000-0000-0000-0000-000000000099"


@pytest.fixture
def cursor():
    assert get_oracle_settings().host.lower() in {"localhost", "127.0.0.1", "::1"}, "Local synthetic LOB tests only"
    original = json.loads((Path(__file__).resolve().parents[1] / "maintenance" / "hierarchy_seed.json").read_text())
    with create_connection() as connection:
        with connection.cursor() as cursor:
            before = fingerprint(read_state(cursor))
            try:
                cursor.execute("SELECT COUNT(*) FROM payors WHERE payor_guid LIKE 'E4000000-%'")
                assert cursor.fetchone()[0] == 0, "Isolated LOB test IDs already exist"
                for number, payor in enumerate(PAYORS):
                    insert_rows(cursor, "PAYORS", [{
                        **original["PAYORS"][0], "payor_guid": payor,
                        "payor_name": f"Synthetic LOB Reader Test {number + 1}",
                        "payor_id": f"SYN-LOB-READER-{number + 1}",
                    }])
                    if number < 2:
                        cursor.execute("""INSERT INTO pfc_config_payor_context
                            (payor_guid, line_of_business, rec_ent_date, rec_ent_user)
                            VALUES (:payor, :lob, DATE '2026-01-01', 'SYN-LOB-READER')""",
                            payor=payor, lob=("HOME_HEALTH", "HOSPICE")[number])
                yield cursor
            finally:
                connection.rollback()
                assert fingerprint(read_state(cursor)) == before


@pytest.mark.parametrize("payor,expected", [(PAYORS[0], "HOME_HEALTH"), (PAYORS[1], "HOSPICE")])
@pytest.mark.parametrize("lock", ["N", "n", " N ", "Y", "y", " y "])
def test_shared_reader_preserves_saved_value_and_lock_mode_normalization(cursor, payor, expected, lock):
    before = fingerprint(read_state(cursor))
    cursor.callproc("pfc_line_of_business.require_defined", [payor, lock])
    assert cursor.callfunc("pfc_line_of_business.get_defined_lob", str, [payor, lock]) == expected
    assert fingerprint(read_state(cursor)) == before


@pytest.mark.parametrize("payor,lock,code", [
    (MISSING_PAYOR, "N", 20050),
    (MISSING_PAYOR, "INVALID", 20050),
    (None, "N", 20050),
    (" " + PAYORS[0], "N", 20050),
    (PAYORS[2], "N", 20053),
    (PAYORS[2], "Y", 20053),
    (PAYORS[2], "INVALID", 20057),
    (PAYORS[0], "INVALID", 20057),
    (PAYORS[0], None, 20057),
    (PAYORS[0], " ", 20057),
])
def test_shared_reader_preserves_require_defined_error_precedence(cursor, payor, lock, code):
    with pytest.raises(oracledb.DatabaseError) as existing:
        cursor.callproc("pfc_line_of_business.require_defined", [payor, lock])
    with pytest.raises(oracledb.DatabaseError) as shared:
        cursor.callfunc("pfc_line_of_business.get_defined_lob", str, [payor, lock])
    assert existing.value.args[0].code == shared.value.args[0].code == code
    assert existing.value.args[0].message.splitlines()[0] == shared.value.args[0].message.splitlines()[0]


def test_shared_reader_retains_unlocked_default(cursor):
    assert cursor.callfunc("pfc_line_of_business.get_defined_lob", str, [PAYORS[0]]) == "HOME_HEALTH"
