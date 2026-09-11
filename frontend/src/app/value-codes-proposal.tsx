import type { ValueCodesCurrentResponse } from "../api/types";
import {
  hospiceValueIsDisabled, setHomeHealthValue, setHospiceValue,
  valueCodesDraftIsComplete, valueCodesDraftMatchesCurrent,
  valueCodesDraftSummary, type ValueCodesDraft,
} from "./value-codes.js";

export const valueCodeCheckboxState = (value: boolean | null) => ({
  checked: value === true,
  "aria-checked": value === null ? "mixed" as const : value,
  ref: (input: HTMLInputElement | null) => { if (input) input.indeterminate = value === null; },
});

export function ValueCodesProposal({ current, draft, disabled = false, onChange }: {
  current: ValueCodesCurrentResponse;
  draft: ValueCodesDraft;
  disabled?: boolean;
  onChange: (draft: ValueCodesDraft) => void;
}) {
  const complete = valueCodesDraftIsComplete(draft);
  const dirty = !valueCodesDraftMatchesCurrent(current, draft);
  return <div className="configuration-stage proposed-configuration">
    <h4 className="configuration-stage-title">Proposed configuration</h4>
    {!complete && <p id="value-codes-choice-help" className="helper">Current on/off values are unavailable. Choose the desired settings before previewing.</p>}
    <fieldset aria-label="Value Codes" aria-describedby={!complete ? "value-codes-choice-help" : undefined} disabled={disabled}>
        {current.line_of_business === "HOME_HEALTH" ? <>
          <label className="choice"><input type="checkbox" {...valueCodeCheckboxState(draft.cbsa)}
            onChange={event => onChange(setHomeHealthValue(draft, "cbsa", event.target.checked))} /><span>Report CBSA</span></label>
          <label className="choice"><input type="checkbox" {...valueCodeCheckboxState(draft.fips)}
            onChange={event => onChange(setHomeHealthValue(draft, "fips", event.target.checked))} /><span>Report FIPS</span></label>
        </> : <>
          <label className="choice"><input type="checkbox" {...valueCodeCheckboxState(draft.care_location_value_code)} disabled={hospiceValueIsDisabled(draft, "care_location_value_code")}
            onChange={event => onChange(setHospiceValue(draft, "care_location_value_code", event.target.checked))} /><span>Report care-location value code 61/G8</span></label>
          <label className="choice"><input type="checkbox" {...valueCodeCheckboxState(draft.patient_entered_value_code)} disabled={hospiceValueIsDisabled(draft, "patient_entered_value_code")}
            onChange={event => onChange(setHospiceValue(draft, "patient_entered_value_code", event.target.checked))} /><span>Report patient-entered value code and amount</span></label>
          <label className="choice"><input type="checkbox" {...valueCodeCheckboxState(draft.covered_days_value_code)}
            onChange={event => onChange(setHospiceValue(draft, "covered_days_value_code", event.target.checked))} /><span>Report value code 80 with days covered</span></label>
        </>}
      </fieldset>
    <p><strong>{valueCodesDraftSummary(current.line_of_business, draft)}</strong></p>
    {complete && <p className={dirty ? "dirty-indicator" : "unchanged-indicator"}>{dirty ? "Proposed configuration differs from the current configuration." : "Matches current configuration."}</p>}
  </div>;
}
