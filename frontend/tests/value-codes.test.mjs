import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  emptyValueCodeSelections, hospiceValueIsDisabled, setHomeHealthValue, setHospiceValue,
  valueCodeSelectionIdentity, valueCodeSelectionsEqual, valueCodesSummary,
} from "../.test-build/app/value-codes.js";
import { CLAIM_FIELD_CATALOG } from "../.test-build/data/claim-field-catalog.js";
import { capabilityIsAvailable, catalogFieldIsAvailable } from "../.test-build/app/workflow.js";

test("39-41 is one grouped Value Codes capability", () => {
  const field = CLAIM_FIELD_CATALOG.find((candidate) => candidate.fieldNumber === "39-41");
  assert.equal(field?.label, "Value Codes");
  assert.equal(field?.capabilityKey, "value-codes");
  const metadata = [{ field_number: "39-41", field_label: "Value Codes", options: [] }];
  assert.equal(capabilityIsAvailable("value-codes", metadata), true);
  assert.equal(catalogFieldIsAvailable(field, metadata), true);
});

test("empty explicit selections describe Off for each Line of Business", () => {
  const selections = emptyValueCodeSelections();
  assert.equal(Object.values(selections).some(Boolean), false);
  assert.equal(valueCodesSummary("HOME_HEALTH", selections), "CBSA Off; FIPS Off");
  assert.equal(valueCodesSummary("HOSPICE", selections), "Value Codes Off");
});

test("Home Health FIPS implies CBSA and clearing CBSA clears FIPS", () => {
  const withFips = setHomeHealthValue(emptyValueCodeSelections(), "fips", true);
  assert.equal(withFips.cbsa, true);
  assert.equal(withFips.fips, true);
  assert.equal(valueCodesSummary("HOME_HEALTH", withFips), "CBSA On; FIPS On");
  assert.deepEqual(setHomeHealthValue(withFips, "cbsa", false), emptyValueCodeSelections());
});

test("Hospice patient-entered is independent from VC80", () => {
  const patientOnly = setHospiceValue(emptyValueCodeSelections(), "patient_entered_value_code", true);
  assert.equal(patientOnly.patient_entered_value_code, true);
  assert.equal(patientOnly.covered_days_value_code, false);
  const withDays = setHospiceValue(patientOnly, "covered_days_value_code", true);
  assert.equal(withDays.patient_entered_value_code, true);
  assert.equal(withDays.covered_days_value_code, true);
  assert.equal(setHospiceValue(withDays, "covered_days_value_code", false).patient_entered_value_code, true);
});

test("Hospice care-location and patient-entered are mutually exclusive while VC80 stays enabled", () => {
  const careOnly = setHospiceValue(emptyValueCodeSelections(), "care_location_value_code", true);
  assert.equal(hospiceValueIsDisabled(careOnly, "patient_entered_value_code"), true);
  assert.equal(hospiceValueIsDisabled(careOnly, "covered_days_value_code"), false);
  assert.strictEqual(setHospiceValue(careOnly, "patient_entered_value_code", true), careOnly);

  const patientOnly = setHospiceValue(emptyValueCodeSelections(), "patient_entered_value_code", true);
  assert.equal(hospiceValueIsDisabled(patientOnly, "care_location_value_code"), true);
  assert.equal(hospiceValueIsDisabled(patientOnly, "covered_days_value_code"), false);
  assert.strictEqual(setHospiceValue(patientOnly, "care_location_value_code", true), patientOnly);
});

test("all six valid Hospice states are representable", () => {
  const none = emptyValueCodeSelections();
  const care = setHospiceValue(none, "care_location_value_code", true);
  const patient = setHospiceValue(none, "patient_entered_value_code", true);
  const days = setHospiceValue(none, "covered_days_value_code", true);
  const states = [none, care, setHospiceValue(care, "covered_days_value_code", true),
    patient, setHospiceValue(patient, "covered_days_value_code", true), days];
  assert.equal(new Set(states.map((value) => JSON.stringify(value))).size, 6);
  assert.equal(valueCodesSummary("HOSPICE", patient), "Patient-entered value code and amount");
  assert.equal(valueCodesSummary("HOSPICE", states[4]),
    "Patient-entered value code and amount and value code 80 with days covered");
});

test("selection identity includes saved LOB and every structured flag", () => {
  const context = { payor_guid: "payor", plan_guid: null, pfc_guid: "pfc", audit_user: "audit" };
  const none = emptyValueCodeSelections();
  const cbsa = { ...none, cbsa: true };
  assert.notEqual(valueCodeSelectionIdentity(context, "HOME_HEALTH", none),
    valueCodeSelectionIdentity(context, "HOME_HEALTH", cbsa));
  assert.notEqual(valueCodeSelectionIdentity(context, "HOME_HEALTH", none),
    valueCodeSelectionIdentity(context, "HOSPICE", none));
  assert.notEqual(valueCodeSelectionIdentity(context, "HOME_HEALTH", none),
    valueCodeSelectionIdentity(context, "HOME_HEALTH", { ...none, cbsa: null, fips: null }));
  assert.notEqual(valueCodeSelectionIdentity(context, "HOME_HEALTH", none),
    valueCodeSelectionIdentity({ ...context, plan_guid: "plan" }, "HOME_HEALTH", none));
  assert.equal(valueCodeSelectionsEqual(none, emptyValueCodeSelections()), true);
});

test("editor exposes LOB-specific controls and keeps diagnostics gated", () => {
  const root = dirname(dirname(fileURLToPath(import.meta.url)));
  const source = readFileSync(join(root, "src", "app", "value-codes-editor.tsx"), "utf8");
  const proposal = readFileSync(join(root, "src", "app", "value-codes-proposal.tsx"), "utf8");
  assert.match(proposal, /Report CBSA/); assert.match(proposal, /Report FIPS/);
  assert.match(proposal, /Report care-location value code 61\/G8/);
  assert.match(proposal, /Report patient-entered value code and amount/);
  assert.match(proposal, /Report value code 80 with days covered/);
  assert.match(proposal, /disabled=\{hospiceValueIsDisabled\(draft, "care_location_value_code"\)\}/);
  assert.match(proposal, /disabled=\{hospiceValueIsDisabled\(draft, "patient_entered_value_code"\)\}/);
  assert.doesNotMatch(proposal, />A3</);
  assert.match(source, /supportDeveloperMode && <details/);
});
