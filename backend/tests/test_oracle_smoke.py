from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app


pytestmark = pytest.mark.skipif(
    os.getenv("RUN_ORACLE_INTEGRATION") != "1",
    reason="Set RUN_ORACLE_INTEGRATION=1 to use the installed synthetic Oracle POC.",
)


def test_installed_synthetic_oracle_poc_preview():
    with TestClient(app) as client:
        health = client.get("/api/health")
        assert health.status_code == 200
        assert health.json()["oracle"] == "connected"

        options = client.get("/api/options")
        assert options.status_code == 200
        fields = {
            field["field_number"]: field for field in options.json()["fields"]
        }
        assert set(fields) == {"39-41", "77", "80", "81"}
        assert fields["81"]["field_label"] == "Provider Taxonomy"
        assert fields["77"]["field_label"] == "Service Facility"
        assert fields["39-41"] == {
            "field_number": "39-41", "field_label": "Value Codes", "options": []
        }
        assert fields["80"] == {
            "field_number": "80", "field_label": "Remarks", "options": []
        }

        undefined_lob = client.post(
            "/api/config/line-of-business/current",
            json={"payor_guid": "10000000-0000-0000-0000-00000000D001"},
        )
        assert undefined_lob.status_code == 200
        assert undefined_lob.json() == {
            "status": "UNDEFINED", "line_of_business": None,
        }

        defined_lob = client.post(
            "/api/config/line-of-business/current",
            json={"payor_guid": "10000000-0000-0000-0000-00000000D002"},
        )
        assert defined_lob.status_code == 200
        assert defined_lob.json()["line_of_business"] == "HOME_HEALTH"

        for field_number, expected_option in (
            ("81", "PROVIDER_TAXONOMY_OFF"),
            ("77", "SERVICE_FACILITY_NEVER"),
        ):
            current = client.post(
                "/api/config/current",
                json={
                    "payor_guid": "10000000-0000-0000-0000-00000000D002",
                    "plan_guid": None,
                    "field_number": field_number,
                },
            )
            assert current.status_code == 200
            assert current.json()["status"] == "RESOLVED"
            assert current.json()["effective_option_code"] == expected_option

        value_current = client.post("/api/config/value-codes/current", json={
            "payor_guid": "10000000-0000-0000-0000-00000000D002",
            "plan_guid": None,
        })
        assert value_current.status_code == 200
        assert value_current.json()["is_default"] is True
        assert not any(value_current.json()["selections"].values())

        remarks_current = client.post("/api/config/remarks/current", json={
            "payor_guid": "10000000-0000-0000-0000-00000000D002",
            "plan_guid": None,
        })
        assert remarks_current.status_code == 200
        assert remarks_current.json()["mode"] == "DEFAULT"
        assert remarks_current.json()["custom_remark"] is None

        remarks_preview = client.post("/api/config/remarks/preview", json={
            "payor_guid": "10000000-0000-0000-0000-00000000D002",
            "plan_guid": None,
            "mode": "CUSTOM",
            "custom_remark": "Synthetic smoke-test remark",
            "audit_user": "90000000-0000-0000-0000-000000000003",
        })
        assert remarks_preview.status_code == 200
        assert remarks_preview.json()["mode"] == "CUSTOM"
        assert remarks_preview.json()["custom_remark"] == (
            "Synthetic smoke-test remark"
        )
        assert "option" not in remarks_preview.text.lower()

        value_preview = client.post("/api/config/value-codes/preview", json={
            "payor_guid": "10000000-0000-0000-0000-00000000D002",
            "plan_guid": None,
            "selections": {"cbsa": True, "fips": False,
                "care_location_value_code": False,
                "patient_entered_value_code": False,
                "covered_days_value_code": False},
            "audit_user": "90000000-0000-0000-0000-000000000003",
        })
        assert value_preview.status_code == 200
        assert value_preview.json()["display_summary"] == "CBSA"
        assert "recipe" not in value_preview.text.lower()

        preview = client.post(
            "/api/config/preview",
            json={
                "payor_guid": "10000000-0000-0000-0000-00000000D002",
                "plan_guid": None,
                "option_code": "PROVIDER_TAXONOMY_ON",
                "audit_user": "90000000-0000-0000-0000-000000000003",
            },
        )
        assert preview.status_code == 200
        assert preview.json()["status"] in {"PREVIEW", "NO_CHANGE"}
        assert len(preview.json()["state_hash"]) == 64

        service_facility_preview = client.post(
            "/api/config/preview",
            json={
                "payor_guid": "10000000-0000-0000-0000-00000000D002",
                "plan_guid": None,
                "option_code": "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
                "audit_user": "90000000-0000-0000-0000-000000000003",
            },
        )
        assert service_facility_preview.status_code == 200
        service_body = service_facility_preview.json()
        assert service_body["status"] == "PREVIEW"
        assert service_body["option_code"] == (
            "SERVICE_FACILITY_ALWAYS_ADDRESS_YES"
        )
        assert service_body["field_number"] == "77"
        assert len(service_body["state_hash"]) == 64
        target_identifiers = {
            change["target_identifier"]
            for change in service_body["debug_changes"]
            if change["target_identifier"] is not None
        }
        assert len(target_identifiers) >= 3
