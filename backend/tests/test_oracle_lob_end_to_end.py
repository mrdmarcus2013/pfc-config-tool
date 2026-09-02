from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

from backend.app.database import create_connection
from backend.app.main import app


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_INTEGRATION") != "1",
    reason="Set RUN_ORACLE_INTEGRATION=1 to run the synthetic write/reset sequence.",
)

PAYOR = "10000000-0000-0000-0000-00000000D001"
AUDIT = "90000000-0000-0000-0000-00000000D001"
UNMANAGED_GUID = "64000000-0000-0000-0000-000000000099"
UNMANAGED_TYPE = "SYNTHETIC_UNMANAGED"


def _cleanup() -> None:
    connection = create_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """DELETE FROM hcfa_electronic_fields f WHERE EXISTS (
                    SELECT 1 FROM hcfa_electronic_records h
                    WHERE h.electronic_rec_guid = f.electronic_rec_guid
                      AND h.payor_guid = :payor)""",
                payor=PAYOR,
            )
            cursor.execute(
                "DELETE FROM hcfa_electronic_records WHERE payor_guid = :payor",
                payor=PAYOR,
            )
            cursor.execute(
                "DELETE FROM pfc_config_payor_context WHERE payor_guid = :payor",
                payor=PAYOR,
            )
        connection.commit()
    finally:
        connection.close()


def _insert_unmanaged_fixture() -> None:
    connection = create_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """INSERT INTO hcfa_electronic_records (
                    electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
                    record_name, record_type_code, record_size, mandatory_ind,
                    req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
                    type_of_bill, detail_ind, max_number, invoice_ind,
                    form_template_guid, carry_forward_ind, max_carry_forward,
                    sto_proc_name, user_form_template_guid, notes, rec_ent_date,
                    rec_ent_user, rec_mod_date, rec_mod_user, include_record_data_onclaim
                ) SELECT :new_guid, loop_id, contiguity_ind, billing_form_code,
                    'Synthetic unmanaged E2E fixture', :record_type, record_size,
                    mandatory_ind, req_for_claim_ind, payor_type_guid, :payor,
                    'STALE-PLAN', type_of_bill, detail_ind, max_number, invoice_ind,
                    form_template_guid, carry_forward_ind, max_carry_forward,
                    sto_proc_name, user_form_template_guid,
                    'Synthetic unmanaged E2E fixture', SYSDATE, :audit_user, NULL, NULL,
                    include_record_data_onclaim
                FROM hcfa_electronic_records
                WHERE electronic_rec_guid = '30000000-0000-0000-0000-00000000D081'""",
                new_guid=UNMANAGED_GUID,
                record_type=UNMANAGED_TYPE,
                payor=PAYOR,
                audit_user=AUDIT,
            )
            cursor.execute(
                """INSERT INTO hcfa_electronic_fields (
                    field_number, electronic_rec_guid, field_name, record_type_code,
                    sto_proc_name, pic, field_spec, position_from, position_thru,
                    field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
                    repeats, detail_ind, occurs_next, hard_coded_data, field_format,
                    caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user,
                    rec_mod_date, rec_mod_user, include_data_onclaim
                ) SELECT field_number, :new_guid, field_name, :record_type,
                    sto_proc_name, pic, field_spec, position_from, position_thru,
                    field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
                    repeats, detail_ind, occurs_next, hard_coded_data, field_format,
                    caps_ind, required_subelement_ind, SYSDATE, :audit_user, NULL, NULL,
                    include_data_onclaim
                FROM hcfa_electronic_fields
                WHERE electronic_rec_guid = '30000000-0000-0000-0000-00000000D081'""",
                new_guid=UNMANAGED_GUID,
                record_type=UNMANAGED_TYPE,
                audit_user=AUDIT,
            )
        connection.commit()
    finally:
        connection.close()


def test_safe_synthetic_lob_end_to_end_and_restore_baseline():
    _cleanup()
    _insert_unmanaged_fixture()
    try:
        with TestClient(app) as client:
            current = client.post(
                "/api/config/line-of-business/current", json={"payor_guid": PAYOR}
            )
            assert current.json()["status"] == "UNDEFINED"

            saved = client.post("/api/config/line-of-business/save", json={
                "payor_guid": PAYOR, "line_of_business": "HOME_HEALTH",
                "audit_user": AUDIT,
            })
            assert saved.status_code == 200

            field_preview = client.post("/api/config/preview", json={
                "payor_guid": PAYOR, "plan_guid": None,
                "option_code": "PROVIDER_TAXONOMY_ON", "audit_user": AUDIT,
            })
            assert field_preview.status_code == 200
            field_apply = client.post("/api/config/apply", json={
                "payor_guid": PAYOR, "plan_guid": None,
                "option_code": "PROVIDER_TAXONOMY_ON", "audit_user": AUDIT,
                "expected_state_hash": field_preview.json()["state_hash"],
            })
            assert field_apply.json()["status"] == "APPLIED"

            lob_preview = client.post(
                "/api/config/line-of-business/preview-change",
                json={"payor_guid": PAYOR, "requested_line_of_business": "HOSPICE"},
            )
            assert lob_preview.status_code == 200
            assert lob_preview.json()["managed_her_count"] >= 1
            lob_apply = client.post(
                "/api/config/line-of-business/apply-change",
                json={
                    "payor_guid": PAYOR,
                    "requested_line_of_business": "HOSPICE",
                    "expected_state_hash": lob_preview.json()["preview_state_hash"],
                    "audit_user": AUDIT,
                },
            )
            assert lob_apply.json()["status"] == "APPLIED"

            lob_after = client.post(
                "/api/config/line-of-business/current", json={"payor_guid": PAYOR}
            )
            assert lob_after.json()["line_of_business"] == "HOSPICE"
            field_after = client.post("/api/config/current", json={
                "payor_guid": PAYOR, "plan_guid": None, "field_number": "81",
            })
            assert field_after.json()["effective_option_code"] == "PROVIDER_TAXONOMY_OFF"

        connection = create_connection()
        try:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT COUNT(*) FROM hcfa_electronic_records WHERE electronic_rec_guid = :guid",
                    guid=UNMANAGED_GUID,
                )
                assert cursor.fetchone()[0] == 1
                cursor.execute(
                    "SELECT COUNT(*) FROM hcfa_electronic_fields WHERE electronic_rec_guid = :guid",
                    guid=UNMANAGED_GUID,
                )
                assert cursor.fetchone()[0] > 0
            connection.rollback()
        finally:
            connection.close()
    finally:
        _cleanup()
