import type { ClaimFieldCatalogEntry, ClaimFieldSection } from "../types/claim-field";

type FieldGroupLayout =
  | "billing"
  | "patient-details"
  | "admission"
  | "codes"
  | "tail"
  | "services"
  | "insurance"
  | "diagnosis"
  | "procedures"
  | "providers"
  | "other";

interface ClaimFieldGroupDefinition {
  id: string;
  label?: string;
  from: number;
  through: number;
  layout: FieldGroupLayout;
}

interface ClaimSectionDefinition {
  name: ClaimFieldSection;
  range: string;
  groups: readonly ClaimFieldGroupDefinition[];
}

export const CLAIM_SECTION_LAYOUT: readonly ClaimSectionDefinition[] = [
  { name: "Billing Details", range: "1–7", groups: [
    { id: "billing-details", from: 1, through: 7, layout: "billing" },
  ] },
  { name: "Patient", range: "8–30", groups: [
    { id: "patient-details", from: 8, through: 11, layout: "patient-details" },
    { id: "admission", label: "Admission", from: 12, through: 17, layout: "admission" },
    { id: "condition-codes", label: "Condition Codes", from: 18, through: 28, layout: "codes" },
    { id: "patient-other", from: 29, through: 30, layout: "tail" },
  ] },
  { name: "Admissions & Occurrences", range: "31–41", groups: [
    { id: "occurrence", label: "Occurrence", from: 31, through: 34, layout: "codes" },
    { id: "occurrence-span", label: "Occurrence Span", from: 35, through: 36, layout: "codes" },
    { id: "occurrence-other", from: 37, through: 38, layout: "tail" },
    { id: "value-codes", label: "Value Codes", from: 39, through: 41, layout: "codes" },
  ] },
  { name: "Services", range: "42–49", groups: [
    { id: "services", from: 42, through: 49, layout: "services" },
  ] },
  { name: "Insurance", range: "50–65", groups: [
    { id: "payer-billing", label: "Payer & Billing", from: 50, through: 57, layout: "insurance" },
    { id: "subscriber", label: "Subscriber", from: 58, through: 65, layout: "insurance" },
  ] },
  { name: "Diagnosis & Procedure Codes", range: "66–75", groups: [
    { id: "diagnosis-codes", label: "Diagnosis Codes", from: 66, through: 73, layout: "diagnosis" },
    { id: "procedure-codes", label: "Procedure Codes", from: 74, through: 75, layout: "procedures" },
  ] },
  { name: "Providers", range: "76–79", groups: [
    { id: "providers", from: 76, through: 79, layout: "providers" },
  ] },
  { name: "Other", range: "80–81", groups: [
    { id: "other", from: 80, through: 81, layout: "other" },
  ] },
];

export const baseFieldNumber = (field: ClaimFieldCatalogEntry) =>
  Number.parseInt(field.fieldNumber, 10);

