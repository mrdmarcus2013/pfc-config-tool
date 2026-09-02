"""Request and response models for the configuration API."""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints


GuidText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=36)]
PublicOptionCode = Literal[
    "PROVIDER_TAXONOMY_ON",
    "PROVIDER_TAXONOMY_OFF",
    "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
    "SERVICE_FACILITY_ALWAYS_ADDRESS_NO",
    "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES",
    "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO",
    "SERVICE_FACILITY_NEVER",
]
LineOfBusiness = Literal["HOME_HEALTH", "HOSPICE"]
SupportedFieldNumber = Literal["77", "81"]
StateHash = Annotated[
    str,
    StringConstraints(strip_whitespace=True, pattern=r"^[0-9A-F]{64}$"),
]


class HealthResponse(BaseModel):
    application: Literal["ok"] = "ok"
    oracle: Literal["connected", "unavailable"]


class OptionItem(BaseModel):
    option_code: str
    display_label: str


class OptionField(BaseModel):
    field_number: str
    field_label: str
    options: list[OptionItem]


class OptionsResponse(BaseModel):
    fields: list[OptionField]


class PreviewRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    payor_guid: GuidText
    plan_guid: GuidText | None = None
    option_code: PublicOptionCode
    audit_user: GuidText


class ApplyRequest(PreviewRequest):
    expected_state_hash: StateHash


class CurrentConfigurationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    payor_guid: GuidText
    plan_guid: GuidText | None = None
    field_number: SupportedFieldNumber


class CurrentConfigurationDisplay(BaseModel):
    mode: Literal["ALWAYS", "CONDITIONAL", "NEVER"] | None = None
    report_address: Literal["Y", "N"] | None = None
    enabled: bool | None = None


class CurrentConfigurationResponse(BaseModel):
    status: Literal["RESOLVED"]
    field_number: SupportedFieldNumber
    capability: Literal["service-facility", "provider-taxonomy"]
    effective_option_code: PublicOptionCode
    display: CurrentConfigurationDisplay
    pfc_guid: str
    canonical: bool | None = None


class TechnicalChange(BaseModel):
    operation_order: int
    operation_code: str
    target_identifier: str | None = None
    field_number: str | None = None


class ConfigurationResponse(BaseModel):
    status: Literal["PREVIEW", "APPLIED", "NO_CHANGE"]
    option_code: str
    display_label: str
    field_number: str | None = None
    state_hash: str
    change_count: int
    summary: str
    pfc_guid: str | None = None
    debug_changes: list[TechnicalChange] = Field(default_factory=list)


class ErrorBody(BaseModel):
    category: str
    message: str


class ErrorResponse(BaseModel):
    error: ErrorBody


class LineOfBusinessCurrentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    payor_guid: GuidText


class LineOfBusinessCurrentResponse(BaseModel):
    status: Literal["UNDEFINED", "DEFINED"]
    line_of_business: LineOfBusiness | None


class LineOfBusinessSaveRequest(LineOfBusinessCurrentRequest):
    line_of_business: LineOfBusiness
    audit_user: GuidText


class LineOfBusinessSaveResponse(BaseModel):
    status: Literal["SAVED"]
    line_of_business: LineOfBusiness


class LineOfBusinessPreviewRequest(LineOfBusinessCurrentRequest):
    requested_line_of_business: LineOfBusiness


class LineOfBusinessApplyRequest(LineOfBusinessPreviewRequest):
    expected_state_hash: StateHash
    audit_user: GuidText


class ManagedTargetCount(BaseModel):
    billing_form_code: str
    record_type_code: str
    her_count: int
    hef_count: int


class LineOfBusinessChangeResponse(BaseModel):
    status: Literal["CHANGES_REQUIRED", "NO_CHANGE", "APPLIED"]
    changes_required: bool
    current_line_of_business: LineOfBusiness
    requested_line_of_business: LineOfBusiness
    managed_target_count: int
    affected_managed_target_count: int
    managed_her_count: int
    managed_hef_count: int
    preview_state_hash: StateHash
    summary: str
    debug_targets: list[ManagedTargetCount] = Field(default_factory=list)
