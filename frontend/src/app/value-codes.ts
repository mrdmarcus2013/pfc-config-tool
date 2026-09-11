import type { LineOfBusiness, ValueCodeSelections, ValueCodesCurrentResponse } from "../api/types";
import type { FrontendLaunchContext } from "../types/launch-context";

export const emptyValueCodeSelections = (): ValueCodeSelections => ({
  cbsa: false, fips: false, care_location_value_code: false,
  patient_entered_value_code: false, covered_days_value_code: false,
});

export type ValueCodesDraft = { [K in keyof ValueCodeSelections]: boolean | null };

export const valueCodesDraftFromCurrent = (current: ValueCodesCurrentResponse): ValueCodesDraft => {
  if (current.effective_selections != null) return { ...current.effective_selections };
  return current.line_of_business === "HOME_HEALTH"
    ? { ...emptyValueCodeSelections(), cbsa: null, fips: null }
    : { ...emptyValueCodeSelections(), care_location_value_code: null,
      patient_entered_value_code: null, covered_days_value_code: null };
};

export const valueCodesDraftIsComplete = (draft: ValueCodesDraft): draft is ValueCodeSelections =>
  Object.values(draft).every(value => typeof value === "boolean");

export const valueCodesRequestSelections = (draft: ValueCodesDraft): ValueCodeSelections => {
  if (!valueCodesDraftIsComplete(draft)) throw new Error("Choose the desired Value Codes before previewing.");
  return { ...draft };
};

export const valueCodesDraftMatchesCurrent = (
  current: ValueCodesCurrentResponse, draft: ValueCodesDraft,
): boolean => current.effective_selections != null && valueCodesDraftIsComplete(draft)
  && valueCodeSelectionsEqual(current.effective_selections, draft);

export const valueCodesDraftSummary = (lob: LineOfBusiness, draft: ValueCodesDraft): string =>
  valueCodesDraftIsComplete(draft) ? valueCodesSummary(lob, draft) : "Choose the desired on/off settings";

export const valueCodesCurrentSummary = (current: ValueCodesCurrentResponse): string =>
  current.effective_selections != null ? valueCodesSummary(current.line_of_business, current.effective_selections)
    : "Current on/off settings are unavailable";

export const valueCodeSelectionIdentity = (
  context: FrontendLaunchContext, lineOfBusiness: LineOfBusiness,
  selections: ValueCodesDraft,
): string => [context.payor_guid, context.plan_guid ?? "", context.audit_user,
  lineOfBusiness, selections.cbsa, selections.fips,
  selections.care_location_value_code, selections.patient_entered_value_code,
  selections.covered_days_value_code].join("|");

export const valueCodeSelectionsEqual = (left: ValueCodeSelections, right: ValueCodeSelections) =>
  Object.keys(left).every((key) => left[key as keyof ValueCodeSelections] === right[key as keyof ValueCodeSelections]);

export const setHomeHealthValue = (
  current: ValueCodesDraft, key: "cbsa" | "fips", checked: boolean,
): ValueCodesDraft => {
  const next = { ...current, [key]: checked };
  if (key === "fips" && checked) next.cbsa = true;
  if (key === "cbsa" && !checked) next.fips = false;
  return next;
};

export const setHospiceValue = (
  current: ValueCodesDraft,
  key: "care_location_value_code" | "patient_entered_value_code" | "covered_days_value_code",
  checked: boolean,
): ValueCodesDraft => {
  if (checked && key === "care_location_value_code" && current.patient_entered_value_code)
    return current;
  if (checked && key === "patient_entered_value_code" && current.care_location_value_code)
    return current;
  const next = { ...current, [key]: checked };
  if (checked && key === "care_location_value_code") next.patient_entered_value_code = false;
  if (checked && key === "patient_entered_value_code") next.care_location_value_code = false;
  return next;
};

export const hospiceValueIsDisabled = (
  selections: ValueCodesDraft,
  key: "care_location_value_code" | "patient_entered_value_code" | "covered_days_value_code",
): boolean =>
  (key === "care_location_value_code" && selections.patient_entered_value_code === true)
  || (key === "patient_entered_value_code" && selections.care_location_value_code === true);

export const valueCodesSummary = (
  lob: LineOfBusiness, selections: ValueCodeSelections,
): string => {
  if (lob === "HOME_HEALTH") return `CBSA ${selections.cbsa ? "On" : "Off"}; FIPS ${selections.fips ? "On" : "Off"}`;
  if (!Object.values(selections).some(Boolean)) return "Value Codes Off";
  if (selections.patient_entered_value_code && selections.covered_days_value_code)
    return "Patient-entered value code and amount and value code 80 with days covered";
  if (selections.patient_entered_value_code) return "Patient-entered value code and amount";
  if (selections.care_location_value_code && selections.covered_days_value_code)
    return "Care-location value code 61/G8 and value code 80 with days covered";
  if (selections.care_location_value_code) return "Care-location value code 61/G8";
  return "Value code 80 with days covered";
};
