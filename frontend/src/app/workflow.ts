import { ApiClientError } from "../api/client.js";
import type {
  ConfigurationResponse,
  OptionField,
  PreviewRequest,
} from "../api/types";
import {
  CONFIGURATION_CAPABILITIES,
  PROVIDER_TAXONOMY_OPTION_BY_SELECTION,
  SERVICE_FACILITY_OPTION_BY_SELECTION,
  type ProviderTaxonomySelection,
  type PublicOptionCode,
  type ServiceFacilityAddress,
  type ServiceFacilityMode,
} from "../data/configuration-capabilities.js";
import type { FrontendLaunchContext } from "../types/launch-context";
import type { ClaimFieldCatalogEntry } from "../types/claim-field";

export const capabilityIsAvailable = (
  capabilityKey: keyof typeof CONFIGURATION_CAPABILITIES,
  fields: readonly OptionField[],
): boolean => {
  const definition = CONFIGURATION_CAPABILITIES[capabilityKey];
  const field = fields.find((candidate) => candidate.field_number === definition.fieldNumber);
  if (!field) return false;
  const optionCodes = new Set(field.options.map((option) => option.option_code));
  return definition.optionCodes.every((code) => optionCodes.has(code));
};

export const catalogFieldIsAvailable = (
  field: ClaimFieldCatalogEntry,
  fields: readonly OptionField[],
): boolean => Boolean(
  field.capabilityKey && capabilityIsAvailable(field.capabilityKey, fields),
);

export const serviceFacilityOption = (
  mode: ServiceFacilityMode,
  address: ServiceFacilityAddress,
): PublicOptionCode => {
  if (mode === "never") return SERVICE_FACILITY_OPTION_BY_SELECTION.never.no;
  return SERVICE_FACILITY_OPTION_BY_SELECTION[mode][address];
};

export const providerTaxonomyOption = (
  selection: ProviderTaxonomySelection,
): PublicOptionCode => PROVIDER_TAXONOMY_OPTION_BY_SELECTION[selection];

export const previewRequest = (
  context: FrontendLaunchContext,
  optionCode: PublicOptionCode,
): PreviewRequest => ({
  payor_guid: context.payor_guid,
  plan_guid: context.plan_guid,
  option_code: optionCode,
  audit_user: context.audit_user,
});

export const previewIdentity = (
  context: FrontendLaunchContext,
  optionCode: PublicOptionCode,
): string =>
  [context.payor_guid, context.plan_guid ?? "", context.audit_user, optionCode].join("|");

export const actionLabel = (operationCode: string): string => {
  const labels: Record<string, string> = {
    NO_CHANGE: "Already configured as requested",
    REBUILD_OVERRIDE: "Configuration will be updated",
    REMOVE_OVERRIDE: "Existing payor-specific customization will be removed",
    BLOCKED: "Configuration cannot be changed",
  };
  return labels[operationCode] ?? "Configuration component will be reviewed";
};

type ApplicablePreview = Pick<ConfigurationResponse, "status" | "change_count" | "debug_changes">;

export const previewAllowsApply = (preview: ApplicablePreview | null): boolean =>
  Boolean(
    preview &&
      preview.status === "PREVIEW" &&
      preview.change_count > 0 &&
      !preview.debug_changes.some((change) => change.operation_code === "BLOCKED"),
  );

export const PREVIEW_REQUIRED_MESSAGE =
  "Preview is required before changes can be applied.";

export interface EditorActionState {
  applyEnabled: boolean;
  dismissLabel: "Cancel" | "Close";
  configurationCompleted: boolean;
  previewVisible: boolean;
  previewRequired: boolean;
}

export const editorActionState = ({
  dirty,
  preview,
  busy,
  applyCompleted,
}: {
  dirty: boolean;
  preview: ApplicablePreview | null;
  busy: "preview" | "apply" | null;
  applyCompleted: boolean;
}): EditorActionState => {
  const completed = applyCompleted && !dirty;
  return {
    applyEnabled: dirty && previewAllowsApply(preview) && busy === null && !completed,
    dismissLabel: completed ? "Close" : "Cancel",
    configurationCompleted: completed,
    previewVisible: preview === null,
    previewRequired: dirty && preview === null && !completed,
  };
};

export class SingleFlightGate {
  private locked = false;

  tryEnter(): boolean {
    if (this.locked) return false;
    this.locked = true;
    return true;
  }

  exit(): void { this.locked = false; }
}

export const currentPreview = <T>(
  record: { identity: string; response: T } | null,
  identity: string,
): T | null => record?.identity === identity ? record.response : null;

export const previewAfterError = <T>(
  record: T | null,
  category: string,
): T | null => category === "stale_preview" ? null : record;

const SAFE_ERROR_MESSAGES: Record<string, string> = {
  backend_unavailable: "The configuration service is unavailable. Check that the backend is running and try again.",
  option_not_found: "That configuration option is not currently available.",
  configuration_not_found: "No configuration was found for this payor and plan.",
  ambiguous_target: "More than one configuration target was found. Nothing was changed.",
  source_not_found: "A required configuration source is unavailable. Nothing was changed.",
  ambiguous_source: "More than one configuration source was found. Nothing was changed.",
  stale_preview: "Configuration changed since the preview.",
  verification_failure: "The change could not be verified, so it was rolled back.",
  target_not_found: "A required configuration target was not found. Nothing was changed.",
  invalid_request: "The request was not valid. Review the selection and try again.",
  invalid_selection: "That Value Codes selection is not valid for the saved Line of Business.",
  current_state_unsupported: "The current configuration requires support review before it can be changed.",
  database_failure: "The database operation could not be completed safely.",
  application_failure: "The configuration operation failed safely. Nothing was changed.",
  line_of_business_required: "Select and save a Line of Business before configuring claim fields.",
  line_of_business_already_saved: "Line of Business is already saved for this payor.",
  payor_not_found: "The requested payor could not be found.",
  server_failure: "The request could not be completed safely.",
};

export const safeError = (error: unknown): { category: string; message: string } => {
  const category = error instanceof ApiClientError ? error.category : "server_failure";
  return { category, message: SAFE_ERROR_MESSAGES[category] ?? SAFE_ERROR_MESSAGES.server_failure };
};
