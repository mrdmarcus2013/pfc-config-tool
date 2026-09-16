import pytest
from pydantic import ValidationError

from backend.app.models import PreviewRequest, ApplyRequest
from backend.app.services.configuration import ConfigurationService


BASE = dict(payor_guid="SYN-PAYOR", plan_guid=None, audit_user="SYN-AUDIT",
            option_code="PROVIDER_TAXONOMY_CUSTOM")


@pytest.mark.parametrize("model", [PreviewRequest, ApplyRequest])
@pytest.mark.parametrize("code", [None, "", " ", "A" * 9, "A" * 11, "A12345678!", "A123 56789", "é123456789"])
def test_invalid_custom_code_is_rejected(model, code):
    extras = {"expected_state_hash": "A" * 64} if model is ApplyRequest else {}
    with pytest.raises(ValidationError):
        model(**BASE, taxonomy_code=code, **extras)


def test_code_is_normalized_and_restricted_to_custom():
    assert PreviewRequest(**BASE, taxonomy_code="  syn000000a ").taxonomy_code == "SYN000000A"
    for option in ("PROVIDER_TAXONOMY_ON", "PROVIDER_TAXONOMY_OFF", "SERVICE_FACILITY_NEVER"):
        with pytest.raises(ValidationError):
            PreviewRequest(**{**BASE, "option_code": option}, taxonomy_code="SYN000000A")


def test_current_custom_response_preserves_the_exact_code_and_rejects_bad_database_values():
    row = dict(status="RESOLVED", field_number="81", capability="provider-taxonomy",
               effective_option_code="PROVIDER_TAXONOMY_CUSTOM", enabled="Y", pfc_guid="SYN-PFC",
               is_canonical="Y", taxonomy_code="SYN000000A")
    assert ConfigurationService._current_response(row, "81")["display"]["taxonomy_code"] == "SYN000000A"
    from backend.app.errors import ApiError
    for value in (None, "short", "syn000000a"):
        with pytest.raises(ApiError):
            ConfigurationService._current_response({**row, "taxonomy_code": value}, "81")
