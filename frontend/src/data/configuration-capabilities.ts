import type { ClaimFieldCapabilityKey } from "../types/claim-field";

export type ProviderTaxonomyOptionCode =
  | "PROVIDER_TAXONOMY_ON"
  | "PROVIDER_TAXONOMY_OFF"
  | "PROVIDER_TAXONOMY_CUSTOM";

export type ServiceFacilityOptionCode =
  | "SERVICE_FACILITY_ALWAYS_ADDRESS_YES"
  | "SERVICE_FACILITY_ALWAYS_ADDRESS_NO"
  | "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES"
  | "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO"
  | "SERVICE_FACILITY_NEVER";

export type PublicOptionCode =
  | ProviderTaxonomyOptionCode
  | ServiceFacilityOptionCode;

export type ServiceFacilityMode = "always" | "conditional" | "never";
export type ServiceFacilityAddress = "yes" | "no";
export type ProviderTaxonomySelection = "yes" | "no" | "custom";

export interface ConfigurationCapabilityDefinition {
  capabilityKey: ClaimFieldCapabilityKey;
  fieldNumber: string;
  optionCodes: readonly PublicOptionCode[];
  availability: "public-options" | "structured-endpoint";
}

export const CONFIGURATION_CAPABILITIES = {
  "service-facility": {
    capabilityKey: "service-facility",
    fieldNumber: "77",
    availability: "public-options",
    optionCodes: [
      "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
      "SERVICE_FACILITY_ALWAYS_ADDRESS_NO",
      "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES",
      "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO",
      "SERVICE_FACILITY_NEVER",
    ],
  },
  "provider-taxonomy": {
    capabilityKey: "provider-taxonomy",
    fieldNumber: "81",
    availability: "public-options",
    optionCodes: ["PROVIDER_TAXONOMY_ON", "PROVIDER_TAXONOMY_OFF", "PROVIDER_TAXONOMY_CUSTOM"],
  },
  "value-codes": {
    capabilityKey: "value-codes",
    fieldNumber: "39-41",
    optionCodes: [],
    availability: "structured-endpoint",
  },
  "remarks": {
    capabilityKey: "remarks",
    fieldNumber: "80",
    optionCodes: [],
    availability: "structured-endpoint",
  },
} as const satisfies Readonly<
  Record<ClaimFieldCapabilityKey, ConfigurationCapabilityDefinition>
>;

/**
 * The future catalog view activates a row only when GET /api/options returns
 * this field number. Catalog rows remain visible when the capability is absent.
 */
export const CAPABILITY_KEY_BY_API_FIELD_NUMBER = {
  "39-41": "value-codes",
  "77": "service-facility",
  "80": "remarks",
  "81": "provider-taxonomy",
} as const satisfies Readonly<Record<string, ClaimFieldCapabilityKey>>;

export const SERVICE_FACILITY_OPTION_BY_SELECTION = {
  always: {
    yes: "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
    no: "SERVICE_FACILITY_ALWAYS_ADDRESS_NO",
  },
  conditional: {
    yes: "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES",
    no: "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO",
  },
  never: {
    no: "SERVICE_FACILITY_NEVER",
  },
} as const;

export const SERVICE_FACILITY_EDITOR_RULES = {
  addressDisabledWhenReportingMode: "never",
  forcedAddressSelection: "no",
} as const;

export const PROVIDER_TAXONOMY_OPTION_BY_SELECTION = {
  custom: "PROVIDER_TAXONOMY_CUSTOM",
  yes: "PROVIDER_TAXONOMY_ON",
  no: "PROVIDER_TAXONOMY_OFF",
} as const satisfies Readonly<Record<ProviderTaxonomySelection, ProviderTaxonomyOptionCode>>;
