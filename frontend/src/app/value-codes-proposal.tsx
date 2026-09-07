import type { ValueCodesCurrentResponse } from "../api/types";
import {
  hospiceValueIsDisabled, setHomeHealthValue, setHospiceValue,
  valueCodesDisplayedSelections, valueCodesIntentIsValid, valueCodesIntentMatchesCurrent,
  valueCodesIntentSummary, type ValueCodesIntent,
} from "./value-codes.js";

export function ValueCodesProposal({ current, intent, isPlan, onChange }: {
  current: ValueCodesCurrentResponse;
  intent: ValueCodesIntent;
  isPlan: boolean;
  onChange: (intent: ValueCodesIntent) => void;
}) {
  const shown = valueCodesDisplayedSelections(current, intent);
  const valid = valueCodesIntentIsValid(intent);
  const dirty = !valueCodesIntentMatchesCurrent(current, intent);
  return <div className="configuration-stage proposed-configuration">
    <h4 className="configuration-stage-title">Proposed configuration</h4>
    <fieldset><legend>Value Code settings</legend>
      <label className="choice"><input type="radio" name="value-codes-mode" checked={intent.useInherited}
        onChange={() => onChange({ ...intent, useInherited: true })} /><span>Use inherited settings</span></label>
      <label className="choice"><input type="radio" name="value-codes-mode" checked={!intent.useInherited}
        onChange={() => onChange({ ...intent, useInherited: false })} /><span>Customize for this {isPlan ? "plan" : "payor"}</span></label>
    </fieldset>
    {intent.useInherited && <p className="helper">These capabilities come from inherited settings. Choose Customize to change them.</p>}
    {shown === null ? <p className="helper">The inherited capabilities cannot be shown individually. Their settings will be preserved.</p>
      : <fieldset disabled={intent.useInherited}><legend>Value Code capabilities</legend>
        {current.line_of_business === "HOME_HEALTH" ? <>
          <label className="choice"><input type="checkbox" checked={shown.cbsa}
            onChange={event => onChange({ ...intent, selections: setHomeHealthValue(shown, "cbsa", event.target.checked) })} /><span>Report CBSA</span></label>
          <label className="choice"><input type="checkbox" checked={shown.fips}
            onChange={event => onChange({ ...intent, selections: setHomeHealthValue(shown, "fips", event.target.checked) })} /><span>Report FIPS</span></label>
        </> : <>
          <label className="choice"><input type="checkbox" checked={shown.care_location_value_code} disabled={hospiceValueIsDisabled(shown, "care_location_value_code")}
            onChange={event => onChange({ ...intent, selections: setHospiceValue(shown, "care_location_value_code", event.target.checked) })} /><span>Report care-location value code 61/G8</span></label>
          <label className="choice"><input type="checkbox" checked={shown.patient_entered_value_code} disabled={hospiceValueIsDisabled(shown, "patient_entered_value_code")}
            onChange={event => onChange({ ...intent, selections: setHospiceValue(shown, "patient_entered_value_code", event.target.checked) })} /><span>Report patient-entered value code and amount</span></label>
          <label className="choice"><input type="checkbox" checked={shown.covered_days_value_code}
            onChange={event => onChange({ ...intent, selections: setHospiceValue(shown, "covered_days_value_code", event.target.checked) })} /><span>Report value code 80 with days covered</span></label>
        </>}
      </fieldset>}
    <p><strong>{valueCodesIntentSummary(current, intent)}</strong></p>
    {!valid ? <p className="helper">Select at least one capability, or choose Use inherited settings.</p>
      : <p className={dirty ? "dirty-indicator" : "unchanged-indicator"}>{dirty ? "Proposed configuration differs from the current configuration." : "Matches current configuration."}</p>}
  </div>;
}
