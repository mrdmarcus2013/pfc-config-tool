import type {
  ClaimFieldCatalogEntry,
  ClaimFieldCapabilityKey,
  ClaimFieldSection,
} from "../types/claim-field";

type SourceEntry = readonly [string, string, ClaimFieldCapabilityKey?];

const section = (name: ClaimFieldSection, values: readonly SourceEntry[]) =>
  values.map(([fieldNumber, label, capabilityKey]) => ({
    id: `field-${fieldNumber.toLowerCase()}`,
    fieldNumber,
    label,
    section: name,
    capabilityKey: capabilityKey ?? null,
  }));

const numbered = (from: number, through: number, label: string): SourceEntry[] =>
  Array.from({ length: through - from + 1 }, (_, index) => [String(from + index), label]);

const lettered = (field: number, letters: readonly string[], label: string): SourceEntry[] =>
  letters.map((letter) => [`${field}${letter}`, label]);

const entries = [
  ...section("Billing Details", [
    ["1", "Billing Provider Name, Address, and Telephone Number"],
    ["2", "Billing Provider's Designated Pay-to Name and Address"],
    ["3a", "Patient Control Number"], ["3b", "Medical/Health Record Number"],
    ["4", "Type of Bill"], ["5", "Federal Tax Number"],
    ["6", "Statement Covers Period"], ["7", "Unlabeled"],
  ]),
  ...section("Patient", [
    ["8a", "Patient Identifier"], ["8b", "Patient Name"],
    ["9a", "Patient Address — Street"], ["9b", "Patient Address — City"],
    ["9c", "Patient Address — State"], ["9d", "Patient Address — ZIP Code"],
    ["9e", "Patient Address — Country Code"], ["10", "Patient Birth Date"],
    ["11", "Patient Sex"], ["12", "Admission/Start of Care Date"],
    ["13", "Admission Hour"], ["14", "Priority (Type) of Admission or Visit"],
    ["15", "Point of Origin for Admission or Visit"],
    ["16", "Discharge Hour"], ["17", "Patient Discharge Status"],
    ...numbered(18, 28, "Condition Code"),
    ["29", "Accident State"], ["30", "Untitled"],
  ]),
  ...section("Admissions & Occurrences", [
    ...lettered(31, ["a", "b"], "Occurrence Code and Date"),
    ...lettered(32, ["a", "b"], "Occurrence Code and Date"),
    ...lettered(33, ["a", "b"], "Occurrence Code and Date"),
    ...lettered(34, ["a", "b"], "Occurrence Code and Date"),
    ...lettered(35, ["a", "b"], "Occurrence Span Code and Dates"),
    ...lettered(36, ["a", "b"], "Occurrence Span Code and Dates"),
    ["37a", "Unlabeled"], ["37b", "Unlabeled"],
    ["38", "Responsible Party Name and Address"],
    ["39-41", "Value Codes", "value-codes"],
    ...lettered(39, ["b", "c", "d"], "Value Code and Amount"),
    ...lettered(40, ["a", "b", "c", "d"], "Value Code and Amount"),
    ...lettered(41, ["a", "b", "c", "d"], "Value Code and Amount"),
  ]),
  ...section("Services", [
    ["42", "Revenue Code"],
    ["43", "Revenue Code Description"],
    ["44", "HCPCS/Accommodation Rates/HIPPS Rate Codes"],
    ["45", "Service Date"], ["46", "Service Units"],
    ["47", "Total Charges"], ["48", "Non-Covered Charges"], ["49", "Unlabeled"],
  ]),
  ...section("Insurance", [
    ...lettered(50, ["a", "b", "c"], "Payer Identification"),
    ...lettered(51, ["a", "b", "c"], "Health Plan Identification Number"),
    ...lettered(52, ["a", "b", "c"], "Release of Information"),
    ...lettered(53, ["a", "b", "c"], "Assignment of Benefits"),
    ...lettered(54, ["a", "b", "c"], "Prior Payments"),
    ...lettered(55, ["a", "b", "c"], "Estimated Amount Due"),
    ["56", "Billing Provider National Provider Identifier (NPI)"],
    ...lettered(57, ["a", "b", "c"], "Other Provider ID"),
    ...lettered(58, ["a", "b", "c"], "Insured's Name"),
    ...lettered(59, ["a", "b", "c"], "Patient's Relationship to Insured"),
    ...lettered(60, ["a", "b", "c"], "Insured's Unique ID"),
    ...lettered(61, ["a", "b", "c"], "Insurance Group Name"),
    ...lettered(62, ["a", "b", "c"], "Insurance Group Number"),
    ...lettered(63, ["a", "b", "c"], "Treatment Authorization Code"),
    ...lettered(64, ["a", "b", "c"], "Document Control Number"),
    ...lettered(65, ["a", "b", "c"], "Employer Name"),
  ]),
  ...section("Diagnosis & Procedure Codes", [
    ["66", "Diagnosis and Procedure Code Qualifier"],
    ["67", "Principal Diagnosis Code and Present on Admission Indicator"],
    ...lettered(67, ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q"], "Other Diagnosis Code and Present on Admission Indicator"),
    ["68", "Unlabeled"], ["69", "Admitting Diagnosis Code"],
    ...lettered(70, ["a", "b", "c"], "Patient Reason for Visit Code"),
    ["71", "Prospective Payment System (PPS) Code"],
    ...lettered(72, ["a", "b", "c"], "External Cause of Injury Code and Present on Admission Indicator"),
    ["73", "Unlabeled"], ["74", "Principal Procedure Code and Date"],
    ...lettered(74, ["a", "b", "c", "d", "e"], "Other Procedure Code and Date"),
    ["75", "Unlabeled"],
  ]),
  ...section("Providers", [
    ["76", "Attending Provider"],
    ["77", "Operating Provider", "service-facility"],
    ["78", "Other Provider"], ["79", "Other Provider"],
  ]),
  ...section("Other", [
    ["80", "Remarks"],
    ["81", "cc", "provider-taxonomy"],
  ]),
];

/** Concise standard labels derived from CMS Chapter 25's CMS-1450 layout. */
export const CLAIM_FIELD_CATALOG: readonly ClaimFieldCatalogEntry[] = entries.map(
  (entry, index) => ({ ...entry, displayOrder: index + 1 }),
);

export const CLAIM_FIELD_CATALOG_COVERAGE = {
  complete: true,
  catalogEntryCount: CLAIM_FIELD_CATALOG.length,
  source: "CMS Medicare Claims Processing Manual, Chapter 25 — Form CMS-1450 Layout Summary",
} as const;
