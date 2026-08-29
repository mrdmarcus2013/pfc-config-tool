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
        assert options.json()["fields"][0]["field_number"] == "81"

        preview = client.post(
            "/api/config/preview",
            json={
                "payor_guid": "10000000-0000-0000-0000-0000000000A1",
                "plan_guid": None,
                "option_code": "PROVIDER_TAXONOMY_ON",
                "audit_user": "90000000-0000-0000-0000-000000000003",
            },
        )
        assert preview.status_code == 200
        assert preview.json()["status"] in {"PREVIEW", "NO_CHANGE"}
        assert len(preview.json()["state_hash"]) == 64
