import type { ClaimFieldCapabilityKey } from "../types/claim-field";

export type ProviderTaxonomyOptionCode =
  | "PROVIDER_TAXONOMY_ON"
  | "PROVIDER_TAXONOMY_OFF";

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
export type ProviderTaxonomySelection = "yes" | "no";

export interface ConfigurationCapabilityDefinition {
  capabilityKey: ClaimFieldCapabilityKey;
  fieldNumber: string;
  optionCodes: readonly PublicOptionCode[];
}

export const CONFIGURATION_CAPABILITIES = {
  "service-facility": {
    capabilityKey: "service-facility",
    fieldNumber: "77",
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
    optionCodes: ["PROVIDER_TAXONOMY_ON", "PROVIDER_TAXONOMY_OFF"],
  },
} as const satisfies Readonly<
  Record<ClaimFieldCapabilityKey, ConfigurationCapabilityDefinition>
>;

/**
 * The future catalog view activates a row only when GET /api/options returns
 * this field number. Catalog rows remain visible when the capability is absent.
 */
export const CAPABILITY_KEY_BY_API_FIELD_NUMBER = {
  "77": "service-facility",
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
  yes: "PROVIDER_TAXONOMY_ON",
  no: "PROVIDER_TAXONOMY_OFF",
} as const satisfies Readonly<Record<"yes" | "no", ProviderTaxonomyOptionCode>>;
