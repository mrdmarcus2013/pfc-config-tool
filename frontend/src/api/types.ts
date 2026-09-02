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
  status: "RESOLVED";
  field_number: "77" | "81";
  capability: "service-facility" | "provider-taxonomy";
  effective_option_code: PublicOptionCode;
  display: CurrentConfigurationDisplay;
  pfc_guid: string;
  canonical: boolean | null;
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
