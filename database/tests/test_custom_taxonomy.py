"""Synthetic Oracle taxonomy transitions. All fixtures and writes roll back."""
import os

import oracledb
import pytest

from database.tests.test_configuration_validation import (
    oracle_cursor, scenario, record_unit, field_multiset,
)
from database.tests.plan_fixtures import PAYORS, plan, database_state
from database.maintenance.rebuild_hierarchy import fingerprint, procedure_row

pytestmark = pytest.mark.skipif(os.getenv("RUN_ORACLE_VALIDATION") != "1",
                                reason="Local rollback-only Oracle tests")


def change(cursor, option="PROVIDER_TAXONOMY_CUSTOM", code="SYN000000A",
           mode="PREVIEW", state_hash=None, selected_plan=plan(0, 1)):
    with cursor.connection.cursor() as summary, cursor.connection.cursor() as changes:
        cursor.callproc("pfc_apply_option", [PAYORS[0], selected_plan, option, "SYN-AUDIT",
                                           mode, state_hash, summary, changes, code])
        return dict(zip([c[0].lower() for c in summary.description], summary.fetchone()))


def current(cursor, selected_plan=plan(0, 1)):
    return procedure_row(cursor, "pfc_get_current_config", [PAYORS[0], selected_plan, "81"])


def apply(cursor, **kwargs):
    preview = change(cursor, **kwargs)
    return change(cursor, mode="APPLY", state_hash=preview["state_hash"], **kwargs)


def unit_fingerprint(cursor, selected_plan):
    her, fields = record_unit(cursor, PAYORS[0], selected_plan)
    return fingerprint({"her": [her], "fields": fields})


def test_custom_roundtrip_hash_and_transitions_preserve_other_scopes(scenario):
    parent = unit_fingerprint(scenario, None)
    sibling = unit_fingerprint(scenario, plan(0, 2))
    _, source_fields = record_unit(scenario, PAYORS[0], None)
    before = fingerprint(database_state(scenario))
    first = change(scenario, code=" syn000000a ")
    second = change(scenario, code="SYN000000B")
    assert first["state_hash"] != second["state_hash"]
    assert fingerprint(database_state(scenario)) == before
    with pytest.raises(oracledb.DatabaseError, match="ORA-20036"):
        change(scenario, code="SYN000000B", mode="APPLY", state_hash=first["state_hash"])
    assert fingerprint(database_state(scenario)) == before
    apply(scenario, code=" syn000000a ")
    assert current(scenario)["taxonomy_code"] == "SYN000000A"
    assert current(scenario)["effective_option_code"] == "PROVIDER_TAXONOMY_CUSTOM"
    her, fields = record_unit(scenario, PAYORS[0], plan(0, 1))
    assert her["sto_proc_name"] == "RETURN_1"
    target = next(f for f in fields if f["field_name"] == "PRV03")
    assert target["sto_proc_name"] is None
    assert target["hard_coded_data"] == "SYN000000A"
    assert field_multiset([f for f in fields if f["field_name"] != "PRV03"]) == field_multiset([f for f in source_fields if f["field_name"] != "PRV03"])
    assert change(scenario)["status"] == "NO_CHANGE"
    apply(scenario, code="SYN000000B")
    assert current(scenario)["taxonomy_code"] == "SYN000000B"
    apply(scenario, option="PROVIDER_TAXONOMY_OFF", code=None)
    assert current(scenario)["enabled"] == "N"
    _, fields = record_unit(scenario, PAYORS[0], plan(0, 1))
    assert next(f for f in fields if f["field_name"] == "PRV03")["hard_coded_data"] is None
    apply(scenario)
    apply(scenario, option="PROVIDER_TAXONOMY_ON", code=None)
    assert current(scenario)["effective_option_code"] == "PROVIDER_TAXONOMY_ON"
    assert current(scenario)["taxonomy_code"] is None
    assert unit_fingerprint(scenario, None) == parent
    assert unit_fingerprint(scenario, plan(0, 2)) == sibling


def test_inherited_fixed_code_uses_minimal_overrides(scenario):
    apply(scenario, selected_plan=None)
    assert current(scenario)["taxonomy_code"] == "SYN000000A"
    assert change(scenario)["status"] == "NO_CHANGE"
    apply(scenario, code="SYN000000B")
    assert change(scenario)["target_action"] == "REMOVE_OVERRIDE"
    apply(scenario)
    assert current(scenario)["taxonomy_code"] == "SYN000000A"


@pytest.mark.parametrize("code", [None, "", " ", "A" * 9, "A" * 11, "SYN000000!", "é123456789"])
def test_oracle_rejects_invalid_custom_without_writes(scenario, code):
    before = fingerprint(database_state(scenario))
    with pytest.raises(oracledb.DatabaseError, match="ORA-20043"):
        change(scenario, code=code)
    assert fingerprint(database_state(scenario)) == before


def test_oracle_rejects_codes_on_standard(scenario):
    with pytest.raises(oracledb.DatabaseError, match="ORA-20043"):
        change(scenario, option="PROVIDER_TAXONOMY_ON")


def test_api_custom_roundtrip_uses_oracle_and_keeps_test_changes_uncommitted(scenario):
    from fastapi.testclient import TestClient
    from backend.app.main import app, get_configuration_service
    from backend.app.services.configuration import ConfigurationService

    class TransactionLocalConnection:
        """The fixture owns the real rollback; never persist synthetic test setup."""
        commits = 0

        def cursor(self):
            return scenario.connection.cursor()

        def rollback(self):
            pass

        def close(self):
            pass

        def commit(self):
            self.commits += 1

    connection = TransactionLocalConnection()
    service = ConfigurationService(lambda: connection)
    app.dependency_overrides[get_configuration_service] = lambda: service
    request = dict(payor_guid=PAYORS[0], plan_guid=plan(0, 1), audit_user="SYN-AUDIT",
                   option_code="PROVIDER_TAXONOMY_CUSTOM", taxonomy_code=" syn000000a ")
    try:
        with TestClient(app) as client:
            invalid = client.post("/api/config/preview", json={**request, "taxonomy_code": "short"})
            assert invalid.status_code == 422
            preview = client.post("/api/config/preview", json=request)
            assert preview.status_code == 200, preview.text
            assert preview.json()["taxonomy_code"] == "SYN000000A"
            assert connection.commits == 0
            save_request = {**request, "expected_state_hash": preview.json()["state_hash"]}
            stale = client.post("/api/config/apply", json={**save_request, "taxonomy_code": "SYN000000B"})
            assert stale.status_code == 409
            assert connection.commits == 0
            saved = client.post("/api/config/apply", json=save_request)
            assert saved.status_code == 200, saved.text
            assert saved.json()["taxonomy_code"] == "SYN000000A"
            assert connection.commits == 1
            loaded = client.post("/api/config/current", json={
                "payor_guid": PAYORS[0], "plan_guid": plan(0, 1), "field_number": "81",
            })
            assert loaded.status_code == 200, loaded.text
            assert loaded.json()["display"]["taxonomy_code"] == "SYN000000A"
            overview = client.post("/api/config/overview", json={"payor_guid": PAYORS[0], "plan_guid": plan(0, 1)})
            assert overview.status_code == 200, overview.text
            assert "SYN000000A" in overview.text
    finally:
        app.dependency_overrides.pop(get_configuration_service, None)
