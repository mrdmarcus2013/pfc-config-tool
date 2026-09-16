import type { ConfigurationResponse } from "../api/types";
import type {
  PublicOptionCode,
  ServiceFacilityOptionCode,
} from "../data/configuration-capabilities";
import type { ClaimFieldCatalogEntry } from "../types/claim-field";

export interface RequestedConfigurationItem {
  label: string;
  value: string;
}

export interface SupportPreviewPresentation {
  statusLabel: string;
  heading: string;
  message: string;
  requestedConfiguration: readonly RequestedConfigurationItem[];
  changes: readonly string[];
}

export const fieldEditorTitle = (field: ClaimFieldCatalogEntry): string =>
  field.capabilityKey === "provider-taxonomy"
    ? "Field 81cc"
    : `Field ${field.fieldNumber} — ${field.label}`;

const providerPresentation = (
  optionCode: PublicOptionCode,
  preview: ConfigurationResponse,
): SupportPreviewPresentation => {
  const enabled = optionCode !== "PROVIDER_TAXONOMY_OFF";
  const custom = optionCode === "PROVIDER_TAXONOMY_CUSTOM";
  const noChange = preview.status === "NO_CHANGE";
  return {
    statusLabel: noChange ? "Already configured" : "Preview ready",
    heading: noChange ? "Already configured" : "Changes required",
    message: noChange
      ? "The requested configuration matches the current effective configuration."
      : `Provider Taxonomy reporting will be ${enabled ? "enabled" : "disabled"} for this payor.`,
    requestedConfiguration: [
      { label: "Provider Taxonomy", value: custom ? `Custom: ${preview.taxonomy_code ?? "Unavailable"}` : enabled ? "Standard" : "None" },
    ],
    changes: noChange ? [] : ["Provider Taxonomy configuration will be updated."],
  };
};

const serviceFacilitySelection = (optionCode: ServiceFacilityOptionCode) => {
  if (optionCode === "SERVICE_FACILITY_NEVER") {
    return { reporting: "Never report service facility", address: "No", disabled: true };
  }
  const conditional = optionCode.startsWith("SERVICE_FACILITY_CONDITIONAL");
  return {
    reporting: conditional
      ? "Only report service facility when care location is not HOME"
      : "Always report service facility",
    address: optionCode.endsWith("_YES") ? "Yes" : "No",
    disabled: false,
  };
};

const serviceFacilityPresentation = (
  optionCode: ServiceFacilityOptionCode,
  preview: ConfigurationResponse,
): SupportPreviewPresentation => {
  const selection = serviceFacilitySelection(optionCode);
  const noChange = preview.status === "NO_CHANGE";
  const changes = noChange ? [] : selection.disabled
    ? [
      "Service facility provider information will be disabled.",
      "Service facility address reporting will be disabled.",
    ]
    : [
      "Service facility provider information will be updated.",
      `Service facility address reporting will be ${selection.address === "Yes" ? "enabled" : "disabled"}.`,
    ];
  return {
    statusLabel: noChange ? "Already configured" : "Preview ready",
    heading: noChange ? "Already configured" : "Changes required",
    message: noChange
      ? "The requested configuration matches the current effective configuration."
      : selection.disabled
        ? "Service Facility reporting will be disabled for this payor."
        : optionCode.startsWith("SERVICE_FACILITY_CONDITIONAL")
          ? "Service Facility reporting will occur only when care location is not HOME for this payor."
          : "Service Facility reporting will be updated for this payor.",
    requestedConfiguration: [
      { label: "Service Facility Reporting", value: selection.reporting },
      { label: "Report address", value: selection.address },
    ],
    changes,
  };
};

export const supportPreviewPresentation = (
  optionCode: PublicOptionCode,
  preview: ConfigurationResponse,
): SupportPreviewPresentation => {
  if (preview.debug_changes.some((change) => change.operation_code === "BLOCKED")) {
    const requested = optionCode.startsWith("PROVIDER_TAXONOMY")
      ? providerPresentation(optionCode, preview).requestedConfiguration
      : serviceFacilityPresentation(optionCode as ServiceFacilityOptionCode, preview).requestedConfiguration;
    return {
      statusLabel: "Change unavailable",
      heading: "Configuration cannot be changed",
      message: "The current configuration prevents this request from being applied.",
      requestedConfiguration: requested,
      changes: [],
    };
  }
  return optionCode.startsWith("PROVIDER_TAXONOMY")
    ? providerPresentation(optionCode, preview)
    : serviceFacilityPresentation(optionCode as ServiceFacilityOptionCode, preview);
};
