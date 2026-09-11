import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ValueCodesProposal, valueCodeCheckboxState } from "../.test-build/app/value-codes-proposal.js";
import {
  emptyValueCodeSelections, valueCodesDraftFromCurrent, valueCodesRequestSelections,
  valueCodesDraftIsComplete, valueCodesDraftMatchesCurrent, valueCodesDraftSummary,
  valueCodesCurrentSummary,
} from "../.test-build/app/value-codes.js";

const flags = values => ({ ...emptyValueCodeSelections(), ...values });
const inherited = flags({ cbsa: true, fips: true });
const current = overrides => ({
  configuration_status: "RESOLVED", line_of_business: "HOME_HEALTH", is_default: true,
  selections: flags(), effective_selections: inherited, inherited_selections: inherited,
  canonical_status: "INHERITED", display_summary: "CBSA and FIPS (inherited)",
  pfc_guid: "SYN-PFC", debug: {}, ...overrides,
});
const render = (response, draft = valueCodesDraftFromCurrent(response), disabled = false) =>
  renderToStaticMarkup(React.createElement(ValueCodesProposal, { current: response, draft, disabled, onChange() {} }));
const checkboxStates = html => [...html.matchAll(/<input\b[^>]*type="checkbox"[^>]*>/g)]
  .map(([tag]) => /aria-checked="mixed"/.test(tag) ? null : /checked=""/.test(tag));
const inputs = node => !React.isValidElement(node) ? [] : [
  ...(node.type === "input" ? [node] : []),
  ...React.Children.toArray(node.props.children).flatMap(inputs),
];
// Invoke the actual proposal handlers without claiming mounted-browser coverage.
const proposal = response => {
  let draft = valueCodesDraftFromCurrent(response);
  return {
    get draft() { return draft; },
    change(index, checked) {
      const view = ValueCodesProposal({ current: response, draft, onChange: next => { draft = next; } });
      inputs(view)[index].props.onChange({ target: { checked } });
    },
  };
};

test("Home Health effective settings render as directly editable On/Off checkboxes without mode choices", () => {
  for (const [values, summary] of [
    [flags(), "CBSA Off; FIPS Off"],
    [flags({ cbsa: true }), "CBSA On; FIPS Off"],
    [inherited, "CBSA On; FIPS On"],
  ]) {
    const response = current({ effective_selections: values, inherited_selections: values });
    const html = render(response);
    assert.deepEqual(checkboxStates(html), [values.cbsa, values.fips]);
    assert.doesNotMatch(html, /type="radio"|Use inherited settings|Customize|disabled=""/);
    assert.match(html, /Matches current configuration/);
    assert.ok(html.includes(summary));
    assert.equal(valueCodesCurrentSummary(response), summary);
    assert.equal(valueCodesDraftMatchesCurrent(response, valueCodesDraftFromCurrent(response)), true);
  }
});

test("a recognized effective override stays checked even when its inherited parent is unknown", () => {
  const response = current({ is_default: false, inherited_selections: null,
    canonical_status: "CANONICAL_OVERRIDE", selections: inherited });
  assert.deepEqual(checkboxStates(render(response)), [true, true]);
  assert.equal(valueCodesDraftIsComplete(valueCodesDraftFromCurrent(response)), true);
  assert.equal(valueCodesCurrentSummary(response), "CBSA On; FIPS On");
});

test("direct checkbox handlers can turn inherited FIPS off and then turn every capability off", () => {
  const response = current();
  const view = proposal(response);
  view.change(1, false);
  assert.deepEqual(view.draft, flags({ cbsa: true }));
  assert.equal(valueCodesDraftMatchesCurrent(response, view.draft), false);
  view.change(0, false);
  assert.deepEqual(valueCodesRequestSelections(view.draft), flags());
  assert.equal(valueCodesDraftIsComplete(view.draft), true);
  assert.deepEqual(checkboxStates(render(response, view.draft)), [false, false]);
  assert.match(render(response, view.draft), /CBSA Off; FIPS Off/);
  assert.doesNotMatch(render(response, view.draft), /Default|inherited|Select at least one/);
  assert.deepEqual(response.effective_selections, inherited, "editing must not mutate the cached current response");
});

test("unknown or missing Home Health effective metadata stays indeterminate instead of becoming Off", () => {
  for (const unknown of [null, undefined]) {
    const response = current({ effective_selections: unknown, inherited_selections: inherited, display_summary: "Default" });
    const draft = valueCodesDraftFromCurrent(response);
    assert.deepEqual(checkboxStates(render(response, draft)), [null, null]);
    assert.equal(draft.cbsa, null);
    assert.equal(draft.fips, null);
    assert.equal(draft.care_location_value_code, false);
    assert.equal(valueCodesDraftIsComplete(draft), false);
    assert.throws(() => valueCodesRequestSelections(draft), /Choose the desired Value Codes/);
    assert.equal(valueCodesCurrentSummary(response), "Current on/off settings are unavailable");
    assert.equal(valueCodesDraftSummary("HOME_HEALTH", draft), "Choose the desired on/off settings");
    assert.match(render(response, draft), /Current on\/off values are unavailable/);
    assert.doesNotMatch(render(response, draft), /CBSA Off|FIPS Off|Matches current configuration/);
  }
});

test("checkbox refs expose mixed unknown state and clear indeterminate after an explicit choice", () => {
  const input = { indeterminate: false };
  const unknown = valueCodeCheckboxState(null);
  assert.equal(unknown.checked, false);
  assert.equal(unknown["aria-checked"], "mixed");
  unknown.ref(input);
  assert.equal(input.indeterminate, true);
  for (const value of [true, false]) {
    const known = valueCodeCheckboxState(value);
    assert.equal(known.checked, value);
    assert.equal(known["aria-checked"], value);
    known.ref(input);
    assert.equal(input.indeterminate, false);
    known.ref(null);
  }
});

test("Home Health dependencies resolve unknown pairs only when the choice determines both values", () => {
  const unknown = current({ effective_selections: null });
  const fipsOn = proposal(unknown);
  fipsOn.change(1, true);
  assert.deepEqual(valueCodesRequestSelections(fipsOn.draft), inherited);
  const cbsaOff = proposal(unknown);
  cbsaOff.change(0, false);
  assert.deepEqual(valueCodesRequestSelections(cbsaOff.draft), flags());

  const cbsaOn = proposal(unknown);
  cbsaOn.change(0, true);
  assert.equal(cbsaOn.draft.fips, null);
  assert.throws(() => valueCodesRequestSelections(cbsaOn.draft), /Choose/);
  cbsaOn.change(1, false);
  assert.deepEqual(valueCodesRequestSelections(cbsaOn.draft), flags({ cbsa: true }));

  const fipsOff = proposal(unknown);
  fipsOff.change(1, false);
  assert.equal(fipsOff.draft.cbsa, null);
  assert.throws(() => valueCodesRequestSelections(fipsOff.draft), /Choose/);
});

test("all six recognized Hospice states render directly without Home Health or mode controls", () => {
  for (const values of [
    {}, { care_location_value_code: true }, { care_location_value_code: true, covered_days_value_code: true },
    { patient_entered_value_code: true }, { patient_entered_value_code: true, covered_days_value_code: true },
    { covered_days_value_code: true },
  ]) {
    const capabilities = flags(values);
    const response = current({ line_of_business: "HOSPICE", effective_selections: capabilities, inherited_selections: capabilities });
    assert.deepEqual(checkboxStates(render(response)), [capabilities.care_location_value_code, capabilities.patient_entered_value_code, capabilities.covered_days_value_code]);
    assert.doesNotMatch(render(response), /Report CBSA|Report FIPS|type="radio"|Customize|Use inherited settings/);
    assert.deepEqual(valueCodesRequestSelections(valueCodesDraftFromCurrent(response)), capabilities);
  }
  assert.equal(valueCodesCurrentSummary(current({ line_of_business: "HOSPICE", effective_selections: flags() })), "Value Codes Off");
});

test("unknown Hospice requires explicit choices and resolves the mutually exclusive capability", () => {
  const response = current({ line_of_business: "HOSPICE", effective_selections: null });
  assert.deepEqual(checkboxStates(render(response)), [null, null, null]);
  for (const [selectedIndex, expected] of [[0, "care_location_value_code"], [1, "patient_entered_value_code"]]) {
    const view = proposal(response);
    view.change(selectedIndex, true);
    assert.equal(view.draft[expected], true);
    assert.equal(view.draft[selectedIndex === 0 ? "patient_entered_value_code" : "care_location_value_code"], false);
    assert.equal(view.draft.covered_days_value_code, null);
    assert.throws(() => valueCodesRequestSelections(view.draft), /Choose/);
    view.change(2, false);
    assert.deepEqual(valueCodesRequestSelections(view.draft), flags({ [expected]: true }));
  }
  const off = proposal(response);
  off.change(0, false);
  off.change(1, false);
  assert.equal(valueCodesDraftIsComplete(off.draft), false);
  off.change(2, false);
  assert.deepEqual(valueCodesRequestSelections(off.draft), flags());
});

test("a refreshed parent does not replace the explicitly selected draft after a stale preview", () => {
  const previous = current();
  const draft = flags();
  const refreshed = current({ inherited_selections: flags({ cbsa: true }), effective_selections: flags({ cbsa: true }) });
  assert.deepEqual(checkboxStates(render(previous, draft)), [false, false]);
  assert.deepEqual(checkboxStates(render(refreshed, draft)), [false, false]);
  assert.equal(valueCodesDraftMatchesCurrent(refreshed, draft), false);
  assert.equal(valueCodesCurrentSummary(refreshed), "CBSA On; FIPS Off");
  assert.deepEqual(valueCodesRequestSelections(draft), flags());
});

test("post-Apply comparison uses actual capabilities even when minimal overrides return to inheritance", () => {
  const off = flags();
  assert.equal(valueCodesDraftMatchesCurrent(current({ effective_selections: off }), off), true);
  assert.equal(valueCodesDraftMatchesCurrent(current({ is_default: false, effective_selections: off }), off), true);
  assert.equal(valueCodesDraftMatchesCurrent(current(), off), false);
  assert.equal(valueCodesDraftMatchesCurrent(current({ effective_selections: null }), off), false);
  assert.equal(valueCodesDraftMatchesCurrent(current(), inherited), true);
});

test("busy proposals disable their controls without changing the selected values", () => {
  const response = current();
  const draft = valueCodesDraftFromCurrent(response);
  assert.match(render(response, draft, true), /<fieldset[^>]*disabled=""/);
  assert.deepEqual(checkboxStates(render(response, draft, true)), [true, true]);
  assert.doesNotMatch(render(response, draft, false), /disabled=""/);
});

test("draft initialization and request construction do not share mutable current-state objects", () => {
  const response = current();
  const draft = valueCodesDraftFromCurrent(response);
  const request = valueCodesRequestSelections(draft);
  assert.notStrictEqual(draft, response.effective_selections);
  assert.notStrictEqual(request, draft);
  request.fips = false;
  assert.equal(draft.fips, true);
  assert.equal(response.effective_selections.fips, true);
});
