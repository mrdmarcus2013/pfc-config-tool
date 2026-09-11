export interface ConfigurationOwner {
  target: string;
  level: "PAYOR_PLAN" | "PAYOR" | "USER_TEMPLATE" | "FORM_TEMPLATE" | "BILLING_FORM";
  identifier: string;
}

import type { PublicOptionCode } from "../data/configuration-capabilities";

export interface OptionItem { option_code: string; display_label: string }
export interface OptionField { field_number: string; field_label: string; options: OptionItem[] }
export interface OptionsResponse { fields: OptionField[] }

export interface PreviewRequest {
  payor_guid: string;
  plan_guid: string | null;
  option_code: PublicOptionCode;
  audit_user: string;
}

export interface ApplyRequest extends PreviewRequest { expected_state_hash: string }
export interface CurrentConfigurationRequest {
  payor_guid: string;
  plan_guid: string | null;
  field_number: "77" | "81";
}
export interface CurrentConfigurationDisplay {
  mode: "ALWAYS" | "CONDITIONAL" | "NEVER" | null;
  report_address: "Y" | "N" | null;
  enabled: boolean | null;
}
export interface CurrentConfigurationResponse {
  configuration_owners?: ConfigurationOwner[];
  status: "RESOLVED";
  field_number: "77" | "81";
  capability: "service-facility" | "provider-taxonomy";
  effective_option_code: PublicOptionCode;
  display: CurrentConfigurationDisplay;
  pfc_guid: string;
  canonical: boolean | null;
}
export interface ConfigurationContextRequest {
  payor_guid: string;
  plan_guid: string | null;
}
export interface ConfigurationContextResponse {
  status: "RESOLVED";
  payor_guid: string;
  plan_guid: string | null;
  pfc_guid: string;
  billing_form_code: string;
  form_template_guid: string | null;
  user_form_template_guid: string | null;
  form_template_name?: string | null;
  user_form_template_name?: string | null;
}
export interface SupportPayorContext {
  plan_name?: string | null;
  payor_guid: string;
  payor_name: string;
  payor_id: string | null;
  plan_guid: string | null;
}
export interface SupportPayorContextsResponse {
  contexts: SupportPayorContext[];
}
export interface TechnicalChange {
  operation_order: number;
  operation_code: string;
  target_identifier: string | null;
  field_number: string | null;
}
export interface ConfigurationResponse {
  status: "PREVIEW" | "APPLIED" | "NO_CHANGE";
  option_code: string;
  display_label: string;
  field_number: string | null;
  state_hash: string;
  change_count: number;
  summary: string;
  pfc_guid: string | null;
  debug_changes: TechnicalChange[];
}
export interface ApiErrorBody { error: { category: string; message: string } }

export type LineOfBusiness = "HOME_HEALTH" | "HOSPICE";
export interface LineOfBusinessCurrentRequest { payor_guid: string }
export interface LineOfBusinessCurrentResponse {
  status: "UNDEFINED" | "DEFINED";
  line_of_business: LineOfBusiness | null;
}
export interface LineOfBusinessSaveRequest extends LineOfBusinessCurrentRequest {
  line_of_business: LineOfBusiness;
  audit_user: string;
}
export interface LineOfBusinessSaveResponse {
  status: "SAVED";
  line_of_business: LineOfBusiness;
}
export interface ManagedTargetCount {
  billing_form_code: string;
  record_type_code: string;
  her_count: number;
  hef_count: number;
}
export interface LineOfBusinessPreviewRequest extends LineOfBusinessCurrentRequest {
  requested_line_of_business: LineOfBusiness;
}
export interface LineOfBusinessApplyRequest extends LineOfBusinessPreviewRequest {
  expected_state_hash: string;
  audit_user: string;
}
export interface LineOfBusinessChangeResponse {
  status: "CHANGES_REQUIRED" | "NO_CHANGE" | "APPLIED";
  changes_required: boolean;
  current_line_of_business: LineOfBusiness;
  requested_line_of_business: LineOfBusiness;
  managed_target_count: number;
  affected_managed_target_count: number;
  managed_her_count: number;
  managed_hef_count: number;
  preview_state_hash: string;
  summary: string;
  debug_targets: ManagedTargetCount[];
}

export interface ValueCodeSelections {
  cbsa: boolean;
  fips: boolean;
  care_location_value_code: boolean;
  patient_entered_value_code: boolean;
  covered_days_value_code: boolean;
}
export interface ValueCodesCurrentRequest { payor_guid: string; plan_guid: string | null }
export interface ValueCodesChangeRequest extends ValueCodesCurrentRequest {
  selections: ValueCodeSelections;
  empty_selection_behavior?: "INHERIT" | "OFF";
  audit_user: string;
}
export interface ValueCodesApplyRequest extends ValueCodesChangeRequest { expected_state_hash: string }
export interface ValueCodesCurrentResponse {
  configuration_owners?: ConfigurationOwner[];
  configuration_status: "RESOLVED";
  line_of_business: LineOfBusiness;
  is_default: boolean;
  selections: ValueCodeSelections;
  effective_selections: ValueCodeSelections | null;
  inherited_selections: ValueCodeSelections | null;
  canonical_status: string;
  display_summary: string;
  pfc_guid: string;
  debug: Record<string, unknown>;
}
export interface ValueCodesChangeResponse {
  status: "PREVIEW" | "APPLIED" | "NO_CHANGE";
  is_default: boolean;
  selections: ValueCodeSelections;
  display_summary: string;
  state_hash: string;
  change_count: number;
  summary: string;
  pfc_guid: string | null;
  debug_changes: TechnicalChange[];
}

export type RemarksMode = "DEFAULT" | "CUSTOM";
export interface RemarksCurrentRequest { payor_guid: string; plan_guid: string | null }
export interface RemarksChangeRequest extends RemarksCurrentRequest {
  mode: RemarksMode;
  custom_remark: string | null;
  audit_user: string;
}
export interface RemarksApplyRequest extends RemarksChangeRequest {
  expected_state_hash: string;
}
export interface RemarksCurrentResponse {
  configuration_owners?: ConfigurationOwner[];
  configuration_status: "RESOLVED";
  line_of_business: LineOfBusiness;
  mode: RemarksMode;
  custom_remark: string | null;
  canonical_status: string;
  display_summary: string;
  pfc_guid: string;
  debug: Record<string, unknown>;
}
export interface RemarksChangeResponse {
  status: "PREVIEW" | "APPLIED" | "NO_CHANGE";
  mode: RemarksMode;
  custom_remark: string | null;
  display_summary: string;
  state_hash: string;
  change_count: number;
  summary: string;
  pfc_guid: string | null;
  debug_changes: TechnicalChange[];
}

export interface ConfigurationOverviewResponse {
  fields: {
    [K in "77" | "81" | "39-41" | "80"]: {
      status: "RESOLVED" | "UNAVAILABLE" | "LOB_REQUIRED";
      current: (K extends "39-41" ? ValueCodesCurrentResponse : K extends "80" ? RemarksCurrentResponse : CurrentConfigurationResponse) | null;
      error?: { category: string; message: string } | null;
    };
  };
}
export interface PayorCopyRequest {
  source_payor_guid: string;
  source_plan_guid: string | null;
  destination_payor_guid: string;
  audit_user: string;
}

export interface PayorCopyResponse {
  status: "READY" | "NO_CHANGE" | "APPLIED";
  state_hash: string;
  source_pfc_guid: string;
  source_form_template: string;
  source_user_template: string;
  billing_form_code: string;
  line_of_business: "HOME_HEALTH" | "HOSPICE";
  records_copied: number;
  records_kept: number;
  records_normalized: number;
  records_removed: number;
  plan_records_removed: number;
  fields_copied: number;
  fields_removed: number;
  template_contexts_updated: number;
  contexts: { pfc_guid: string; plan_guid: string | null; label: string; templates_changed: boolean;
    form_template_before: string; user_template_before: string }[];
  changes: { label: string; action: "KEEP" | "REMOVE" | "COPY"; level: string; record_type: string }[];
}
