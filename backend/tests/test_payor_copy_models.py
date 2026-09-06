"""Preserve the existing Copy API contract while relocating its models."""

import pytest
from pydantic import ValidationError

from backend.app.models_payor_copy import CopyApplyRequest, CopyContext, CopyPreviewRequest


@pytest.mark.parametrize("state_hash", ["A" * 64, "a" * 64, "aB09" * 16])
def test_copy_hash_preserves_case_and_request_defaults(state_hash):
    request = CopyApplyRequest(
        source_payor_guid=" SYN-SOURCE ",
        destination_payor_guid=" SYN-DESTINATION ",
        audit_user=" SYN-USER ",
        expected_state_hash=state_hash,
    )
    assert request.model_dump() == {
        "source_payor_guid": "SYN-SOURCE",
        "source_plan_guid": None,
        "destination_payor_guid": "SYN-DESTINATION",
        "audit_user": "SYN-USER",
        "expected_state_hash": state_hash,
    }


@pytest.mark.parametrize("state_hash", [" " + "A" * 64, "A" * 64 + " "])
def test_copy_hash_does_not_trim_whitespace(state_hash):
    with pytest.raises(ValidationError):
        CopyApplyRequest(
            source_payor_guid="SYN-SOURCE",
            destination_payor_guid="SYN-DESTINATION",
            audit_user="SYN-USER",
            expected_state_hash=state_hash,
        )


def test_copy_context_retains_default_template_labels():
    context = CopyContext(
        pfc_guid="SYN-PFC", plan_guid=None,
        label="Payor-level settings", templates_changed=False,
    )
    assert context.form_template_before == "Unavailable"
    assert context.user_template_before == "Unavailable"


def test_service_model_imports_remain_compatible():
    from backend.app.services import payor_copy

    assert payor_copy.CopyPreviewRequest is CopyPreviewRequest
    assert payor_copy.CopyApplyRequest is CopyApplyRequest
    assert payor_copy.CopyContext is CopyContext
