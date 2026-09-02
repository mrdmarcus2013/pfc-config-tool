import type { LineOfBusiness, ValueCodeSelections } from "../api/types";
import type { FrontendLaunchContext } from "../types/launch-context";

export const emptyValueCodeSelections = (): ValueCodeSelections => ({
  cbsa: false, fips: false, care_location_value_code: false,
  patient_entered_value_code: false, covered_days_value_code: false,
});

export const valueCodeSelectionIdentity = (
  context: FrontendLaunchContext, lineOfBusiness: LineOfBusiness,
  selections: ValueCodeSelections,
): string => [context.payor_guid, context.plan_guid ?? "", context.audit_user,
  lineOfBusiness, selections.cbsa, selections.fips,
  selections.care_location_value_code, selections.patient_entered_value_code,
  selections.covered_days_value_code].join("|");

export const valueCodeSelectionsEqual = (left: ValueCodeSelections, right: ValueCodeSelections) =>
  Object.keys(left).every((key) => left[key as keyof ValueCodeSelections] === right[key as keyof ValueCodeSelections]);

export const setHomeHealthValue = (
  current: ValueCodeSelections, key: "cbsa" | "fips", checked: boolean,
): ValueCodeSelections => {
  const next = { ...current, [key]: checked };
  if (key === "fips" && checked) next.cbsa = true;
  if (key === "cbsa" && !checked) next.fips = false;
  return next;
};

export const setHospiceValue = (
  current: ValueCodeSelections,
  key: "care_location_value_code" | "patient_entered_value_code" | "covered_days_value_code",
  checked: boolean,
): ValueCodeSelections => {
  if (checked && key === "care_location_value_code" && current.patient_entered_value_code)
    return current;
  if (checked && key === "patient_entered_value_code" && current.care_location_value_code)
    return current;
  return { ...current, [key]: checked };
};

export const hospiceValueIsDisabled = (
  selections: ValueCodeSelections,
  key: "care_location_value_code" | "patient_entered_value_code" | "covered_days_value_code",
): boolean =>
  (key === "care_location_value_code" && selections.patient_entered_value_code)
  || (key === "patient_entered_value_code" && selections.care_location_value_code);

export const valueCodesSummary = (
  lob: LineOfBusiness, selections: ValueCodeSelections,
): string => {
  if (!Object.values(selections).some(Boolean)) return "Default";
  if (lob === "HOME_HEALTH") return selections.fips ? "CBSA and FIPS" : "CBSA";
  if (selections.patient_entered_value_code && selections.covered_days_value_code)
    return "Patient-entered value code and amount and value code 80 with days covered";
  if (selections.patient_entered_value_code) return "Patient-entered value code and amount";
  if (selections.care_location_value_code && selections.covered_days_value_code)
    return "Care-location value code 61/G8 and value code 80 with days covered";
  if (selections.care_location_value_code) return "Care-location value code 61/G8";
  return "Value code 80 with days covered";
};
