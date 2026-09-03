export type ClaimFieldCapabilityKey =
  | "provider-taxonomy"
  | "service-facility"
  | "value-codes"
  | "remarks";

/** Static, implementation-neutral metadata for one visible claim-form row. */
export interface ClaimFieldCatalogEntry {
  id: string;
  fieldNumber: string;
  label: string;
  section: ClaimFieldSection;
  displayOrder: number;
  capabilityKey: ClaimFieldCapabilityKey | null;
}

export type ClaimFieldSection =
  | "Billing Details"
  | "Patient"
  | "Admissions & Occurrences"
  | "Services"
  | "Insurance"
  | "Diagnosis & Procedure Codes"
  | "Providers"
  | "Other";
