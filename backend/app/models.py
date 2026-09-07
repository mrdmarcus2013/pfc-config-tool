"""Request and response models for the configuration API."""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_validator,
    model_validator,
)


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
REMARKS_CUSTOM_REMARK_MAX_LENGTH = 100
RemarksMode = Literal["DEFAULT", "CUSTOM"]


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


class ConfigurationOwner(BaseModel):
    target: str
    level: Literal["PAYOR_PLAN", "PAYOR", "USER_TEMPLATE", "FORM_TEMPLATE", "BILLING_FORM"]
    identifier: str


class CurrentConfigurationResponse(BaseModel):
    configuration_owners: list[ConfigurationOwner] = Field(default_factory=list)
    status: Literal["RESOLVED"]
    field_number: SupportedFieldNumber
    capability: Literal["service-facility", "provider-taxonomy"]
    effective_option_code: PublicOptionCode
    display: CurrentConfigurationDisplay
    pfc_guid: str
    canonical: bool | None = None


class ConfigurationContextRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    payor_guid: GuidText
    plan_guid: GuidText | None = None


class ConfigurationContextResponse(BaseModel):
    status: Literal["RESOLVED"]
    payor_guid: str
    plan_guid: str | None
    pfc_guid: str
    billing_form_code: str
    form_template_guid: str | None
    user_form_template_guid: str | None

    form_template_name: str | None = None
    user_form_template_name: str | None = None


class SupportPayorContext(BaseModel):
    plan_name: str | None = None
    payor_guid: str
    payor_name: str
    payor_id: str | None
    plan_guid: str | None


class SupportPayorContextsResponse(BaseModel):
    contexts: list[SupportPayorContext]


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


class ValueCodeSelections(BaseModel):
    model_config = ConfigDict(extra="forbid")

    cbsa: bool = False
    fips: bool = False
    care_location_value_code: bool = False
    patient_entered_value_code: bool = False
    covered_days_value_code: bool = False

    @model_validator(mode="after")
    def validate_supported_shape(self) -> "ValueCodeSelections":
        if self.fips and not self.cbsa:
            raise ValueError("Add FIPS requires Add CBSA.")
        if self.care_location_value_code and self.patient_entered_value_code:
            raise ValueError(
                "Care-location and patient-entered Hospice Value Codes cannot be selected together."
            )
        return self


class ValueCodesCurrentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    payor_guid: GuidText
    plan_guid: GuidText | None = None


class ValueCodesChangeRequest(ValueCodesCurrentRequest):
    selections: ValueCodeSelections
    audit_user: GuidText


class ValueCodesApplyRequest(ValueCodesChangeRequest):
    expected_state_hash: StateHash


class ValueCodesCurrentResponse(BaseModel):
    configuration_owners: list[ConfigurationOwner] = Field(default_factory=list)
    configuration_status: Literal["RESOLVED"]
    line_of_business: LineOfBusiness
    is_default: bool
    selections: ValueCodeSelections
    effective_selections: ValueCodeSelections | None
    inherited_selections: ValueCodeSelections | None
    canonical_status: str
    display_summary: str
    pfc_guid: str
    debug: dict[str, object] = Field(default_factory=dict)


class ValueCodesChangeResponse(BaseModel):
    status: Literal["PREVIEW", "APPLIED", "NO_CHANGE"]
    is_default: bool
    selections: ValueCodeSelections
    display_summary: str
    state_hash: StateHash
    change_count: int
    summary: str
    pfc_guid: str | None = None
    debug_changes: list[TechnicalChange] = Field(default_factory=list)


class RemarksCurrentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    payor_guid: GuidText
    plan_guid: GuidText | None = None


class RemarksChangeRequest(RemarksCurrentRequest):
    mode: RemarksMode
    custom_remark: str | None = None
    audit_user: GuidText

    @field_validator("custom_remark", mode="before")
    @classmethod
    def trim_custom_remark(cls, value: object) -> object:
        if isinstance(value, str):
            trimmed = value.strip()
            return trimmed or None
        return value

    @model_validator(mode="after")
    def validate_mode_and_text(self) -> "RemarksChangeRequest":
        if self.mode == "DEFAULT":
            if self.custom_remark is not None:
                raise ValueError("Default Remarks cannot include custom text.")
            return self
        if self.custom_remark is None:
            raise ValueError("Custom remark text is required.")
        if len(self.custom_remark) > REMARKS_CUSTOM_REMARK_MAX_LENGTH:
            raise ValueError(
                "Custom remark text exceeds the configured maximum length."
            )
        return self


class RemarksApplyRequest(RemarksChangeRequest):
    expected_state_hash: StateHash


class RemarksCurrentResponse(BaseModel):
    configuration_owners: list[ConfigurationOwner] = Field(default_factory=list)
    configuration_status: Literal["RESOLVED"]
    line_of_business: LineOfBusiness
    mode: RemarksMode
    custom_remark: str | None
    canonical_status: str
    display_summary: str
    pfc_guid: str
    debug: dict[str, object] = Field(default_factory=dict)


class RemarksChangeResponse(BaseModel):
    status: Literal["PREVIEW", "APPLIED", "NO_CHANGE"]
    mode: RemarksMode
    custom_remark: str | None
    display_summary: str
    state_hash: StateHash
    change_count: int
    summary: str
    pfc_guid: str | None = None
    debug_changes: list[TechnicalChange] = Field(default_factory=list)


class ConfigurationOverviewItem(BaseModel):
    status: Literal["RESOLVED", "UNAVAILABLE", "LOB_REQUIRED"]
    current: CurrentConfigurationResponse | ValueCodesCurrentResponse | RemarksCurrentResponse | None = None
    error: ErrorBody | None = None


class ConfigurationOverviewResponse(BaseModel):
    fields: dict[Literal["77", "81", "39-41", "80"], ConfigurationOverviewItem]
