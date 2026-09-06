"""Request and response models for the separate Payor Copy API."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from backend.app.models import GuidText


class CopyDestinationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    source_payor_guid: GuidText
    source_plan_guid: GuidText | None = None
    audit_user: GuidText


class CopyPreviewRequest(CopyDestinationRequest):
    destination_payor_guid: GuidText


class CopyDestination(BaseModel):
    payor_guid: str
    payor_name: str


class CopyDestinationsResponse(BaseModel):
    destinations: list[CopyDestination]


class CopyApplyRequest(CopyPreviewRequest):
    expected_state_hash: str = Field(pattern=r"^[A-Fa-f0-9]{64}$")


class CopyContext(BaseModel):
    pfc_guid: str
    plan_guid: str | None
    label: str
    templates_changed: bool
    form_template_before: str = "Unavailable"
    user_template_before: str = "Unavailable"


class CopyChange(BaseModel):
    label: str
    action: Literal["KEEP", "REMOVE", "COPY"]
    level: str
    record_type: str


class CopyResponse(BaseModel):
    status: Literal["READY", "NO_CHANGE", "APPLIED"]
    state_hash: str
    source_pfc_guid: str
    billing_form_code: str
    line_of_business: Literal["HOME_HEALTH", "HOSPICE"]
    source_form_template: str = "Unavailable"
    source_user_template: str = "Unavailable"
    records_copied: int
    records_kept: int
    records_normalized: int = 0
    records_removed: int
    plan_records_removed: int
    fields_copied: int
    fields_removed: int
    template_contexts_updated: int
    contexts: list[CopyContext]
    changes: list[CopyChange]
