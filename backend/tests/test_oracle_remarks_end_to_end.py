from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

from backend.app.database import create_connection
from backend.app.main import app


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_INTEGRATION") != "1",
    reason="Set RUN_ORACLE_INTEGRATION=1 for the synthetic Remarks sequence.",
)

PAYOR = "10000000-0000-0000-0000-00000000D001"
AUDIT = "90000000-0000-0000-0000-00000000D001"
SOURCE = "33000000-0000-0000-0000-000000000001"
TARGET = "D23001900NTE182"


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


def _set_source_custom(custom_remark: str) -> None:
    connection = create_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                "UPDATE hcfa_electronic_records SET sto_proc_name = 'RETURN_1' "
                "WHERE electronic_rec_guid = :source_guid",
                source_guid=SOURCE,
            )
            cursor.execute(
                """UPDATE hcfa_electronic_fields
                   SET sto_proc_name = NULL,
                       hard_coded_data = CASE field_number
                           WHEN '00' THEN 'NTE'
                           WHEN '01' THEN 'ADD'
                           WHEN '02' THEN :custom_remark
                       END
                   WHERE electronic_rec_guid = :source_guid
                     AND field_number IN ('00', '01', '02')""",
                source_guid=SOURCE,
                custom_remark=custom_remark,
            )
        connection.commit()
    finally:
        connection.close()


def _restore_source() -> None:
    connection = create_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                "UPDATE hcfa_electronic_records "
                "SET sto_proc_name = 'G_D2300190NTE208_COUNT' "
                "WHERE electronic_rec_guid = :source_guid",
                source_guid=SOURCE,
            )
            cursor.execute(
                """UPDATE hcfa_electronic_fields
                   SET sto_proc_name = CASE WHEN field_number = '02'
                                            THEN 'GET_REMARKS' END,
                       hard_coded_data = CASE field_number
                           WHEN '00' THEN 'NTE'
                           WHEN '01' THEN 'ADD'
                           WHEN '02' THEN NULL
                       END
                   WHERE electronic_rec_guid = :source_guid
                     AND field_number IN ('00', '01', '02')""",
                source_guid=SOURCE,
            )
        connection.commit()
    finally:
        connection.close()


def _current(client: TestClient) -> dict:
    response = client.post("/api/config/remarks/current", json={
        "payor_guid": PAYOR, "plan_guid": None,
    })
    assert response.status_code == 200, response.text
    return response.json()


def _apply(client: TestClient, mode: str, custom_remark: str | None) -> dict:
    request = {
        "payor_guid": PAYOR,
        "plan_guid": None,
        "mode": mode,
        "custom_remark": custom_remark,
        "audit_user": AUDIT,
    }
    preview = client.post("/api/config/remarks/preview", json=request)
    assert preview.status_code == 200, preview.text
    if preview.json()["status"] == "NO_CHANGE":
        return preview.json()
    applied = client.post("/api/config/remarks/apply", json={
        **request, "expected_state_hash": preview.json()["state_hash"],
    })
    assert applied.status_code == 200, applied.text
    assert applied.json()["status"] == "APPLIED"
    return applied.json()


def _change_lob(client: TestClient, requested: str) -> None:
    preview = client.post("/api/config/line-of-business/preview-change", json={
        "payor_guid": PAYOR, "requested_line_of_business": requested,
    })
    assert preview.status_code == 200, preview.text
    applied = client.post("/api/config/line-of-business/apply-change", json={
        "payor_guid": PAYOR,
        "requested_line_of_business": requested,
        "expected_state_hash": preview.json()["preview_state_hash"],
        "audit_user": AUDIT,
    })
    assert applied.status_code == 200, applied.text


def _override_count() -> int:
    connection = create_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT COUNT(*) FROM hcfa_electronic_records
                   WHERE payor_guid = :payor AND record_type_code = :target""",
                payor=PAYOR,
                target=TARGET,
            )
            return cursor.fetchone()[0]
    finally:
        connection.close()


def test_remarks_api_home_health_hospice_redundant_source_and_lob_reset():
    _restore_source()
    _cleanup()
    try:
        with TestClient(app) as client:
            saved = client.post("/api/config/line-of-business/save", json={
                "payor_guid": PAYOR,
                "line_of_business": "HOME_HEALTH",
                "audit_user": AUDIT,
            })
            assert saved.status_code == 200, saved.text

            assert _current(client)["mode"] == "DEFAULT"
            _apply(client, "CUSTOM", "Test custom remark")
            assert _current(client)["custom_remark"] == "Test custom remark"
            _apply(client, "CUSTOM", "Updated custom remark")
            assert _current(client)["custom_remark"] == "Updated custom remark"
            _apply(client, "DEFAULT", None)
            assert _current(client)["mode"] == "DEFAULT"
            assert _override_count() == 0

            _change_lob(client, "HOSPICE")
            _apply(client, "CUSTOM", "Hospice custom remark")
            assert _current(client)["custom_remark"] == "Hospice custom remark"
            _apply(client, "DEFAULT", None)
            assert _current(client)["mode"] == "DEFAULT"

            _set_source_custom("Inherited exact custom")
            no_change = _apply(client, "CUSTOM", "Inherited exact custom")
            assert no_change["status"] == "NO_CHANGE"
            assert _override_count() == 0
            assert _current(client)["mode"] == "DEFAULT"
            _restore_source()

            _apply(client, "CUSTOM", "Reset this custom remark")
            assert _override_count() == 1
            _change_lob(client, "HOME_HEALTH")
            assert _override_count() == 0
            after_reset = _current(client)
            assert after_reset["mode"] == "DEFAULT"
            assert after_reset["line_of_business"] == "HOME_HEALTH"
    finally:
        _restore_source()
        _cleanup()
