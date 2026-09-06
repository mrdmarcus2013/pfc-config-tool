"""Rollback-only integration coverage for the approved hierarchy checkpoint."""
import json
import os

import pytest

from backend.app.database import create_connection
from backend.app.services.configuration import ConfigurationService, _configuration_owners
from backend.app.errors import ApiError
from database.maintenance.rebuild_hierarchy import (
    HERE, fingerprint, read_state, procedure_row, verify_inheritance,
)


def test_owner_parser_preserves_mixed_owners_and_rejects_invalid_data():
    owners = [{"target": "Service facility", "level": "USER_TEMPLATE", "identifier": "SYN_USER"},
              {"target": "Street address", "level": "BILLING_FORM", "identifier": "837I_5010"}]
    assert _configuration_owners({"configuration_owners": json.dumps(owners)}) == owners
    for raw in ('null', '{}', '[]', '[{"target":"x","level":"UNKNOWN","identifier":"x"}]'):
        with pytest.raises(ApiError):
            _configuration_owners({"configuration_owners": raw})


live = pytest.mark.skipif(os.getenv("RUN_ORACLE_HIERARCHY") != "1", reason="Set RUN_ORACLE_HIERARCHY=1 for the approved local checkpoint")


@live
def test_all_payors_inherit_expected_settings_and_owners():
    desired = json.loads((HERE / "hierarchy_seed.json").read_text())
    with create_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SET TRANSACTION READ ONLY")
            assert fingerprint(read_state(cursor)) == fingerprint(desired)
            assert verify_inheritance(cursor, desired) == 26
    service = ConfigurationService()
    row = service.value_codes_current(payor_guid="10000000-0000-0000-0000-0000000000A5", plan_guid=None)
    assert row["display_summary"] == "CBSA and FIPS (inherited)"
    assert row["configuration_owners"][0]["level"] == "USER_TEMPLATE"
    assert row["is_default"] and not any(row["selections"].values())


def change(cursor, payor, option, mode, state_hash=None):
    with cursor.connection.cursor() as summary, cursor.connection.cursor() as changes:
        cursor.callproc("pfc_apply_option", [payor, None, option, "SYN_HIERARCHY_TEST", mode, state_hash, summary, changes])
        names = [d[0].lower() for d in summary.description]
        return dict(zip(names, summary.fetchone()))


def apply_option(cursor, payor, option):
    preview = change(cursor, payor, option, "PREVIEW")
    return change(cursor, payor, option, "APPLY", preview["state_hash"])


@live
def test_template_switching_and_manual_payor_override_with_rollback():
    payor = "10000000-0000-0000-0000-00000000D002"
    with create_connection() as connection:
        with connection.cursor() as cursor:
            before = fingerprint(read_state(cursor))
            try:
                def current():
                    return procedure_row(cursor, "pfc_get_current_config", [payor, None, "81"])
                def template(suffix):
                    cursor.execute("UPDATE pfc SET user_form_template_guid=:g WHERE payor_guid=:p",
                                   g="50000000-0000-0000-0000-00000000C10" + suffix, p=payor)
                assert current()["effective_option_code"] == "PROVIDER_TAXONOMY_OFF"
                template("1")
                assert current()["effective_option_code"] == "PROVIDER_TAXONOMY_ON"
                template("2")
                assert current()["effective_option_code"] == "PROVIDER_TAXONOMY_OFF"
                apply_option(cursor, payor, "PROVIDER_TAXONOMY_ON")
                assert json.loads(current()["configuration_owners"])[0]["level"] == "PAYOR"
                template("3")
                assert current()["effective_option_code"] == "PROVIDER_TAXONOMY_ON"
                apply_option(cursor, payor, "PROVIDER_TAXONOMY_OFF")
                assert json.loads(current()["configuration_owners"])[0]["level"] == "BILLING_FORM"
            finally:
                connection.rollback()
            assert fingerprint(read_state(cursor)) == before


@live
def test_hospice_recipe_preview_apply_and_default_preserve_care_location():
    payor = "C1000000-0000-0000-0000-000000000001"
    with create_connection() as connection:
        with connection.cursor() as cursor:
            before = fingerprint(read_state(cursor))
            try:
                # Override the inherited combined profile with care-location only.
                apply_option(cursor, payor, "VC|HOSPICE|N|N|Y|N|N")
                row = procedure_row(cursor, "pfc_value_codes_api.current_configuration", [payor, None])
                assert row["care_location_value_code"] == "Y" and row["covered_days_value_code"] == "N"
                assert json.loads(row["configuration_owners"])[0]["level"] == "PAYOR"
                apply_option(cursor, payor, "VC|HOSPICE|N|N|N|N|N")
                row = procedure_row(cursor, "pfc_value_codes_api.current_configuration", [payor, None])
                assert row["is_default"] == "Y" and "days covered" in row["display_summary"]
                assert json.loads(row["configuration_owners"])[0]["level"] == "USER_TEMPLATE"
            finally:
                connection.rollback()
            assert fingerprint(read_state(cursor)) == before
