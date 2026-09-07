import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ValueCodesProposal } from "../.test-build/app/value-codes-proposal.js";
import {
  emptyValueCodeSelections, valueCodesIntentFromCurrent, valueCodesRequestSelections,
  valueCodesIntentIsValid, valueCodesIntentMatchesCurrent, valueCodesDisplayedSelections,
} from "../.test-build/app/value-codes.js";

const flags = values => ({ ...emptyValueCodeSelections(), ...values });
const inherited = flags({ cbsa: true, fips: true });
const current = overrides => ({
  configuration_status: "RESOLVED", line_of_business: "HOME_HEALTH", is_default: true,
  selections: flags(), effective_selections: inherited, inherited_selections: inherited,
  canonical_status: "INHERITED", display_summary: "CBSA and FIPS (inherited)",
  pfc_guid: "SYN-PFC", debug: {}, ...overrides,
});

test("refreshing a changed parent preserves reset intent and displays its new inherited flags", () => {
  const previous = current({ is_default: false, effective_selections: flags({ cbsa: true }) });
  const reset = { ...valueCodesIntentFromCurrent(previous), useInherited: true };
  const refreshed = { ...previous, inherited_selections: flags() };
  assert.deepEqual(checkboxStates(render(previous, reset, true)), [true, true]);
  assert.deepEqual(checkboxStates(render(refreshed, reset, true)), [false, false]);
  assert.deepEqual(valueCodesRequestSelections(reset), flags());
  assert.match(render(refreshed, reset, true), /Off \(inherited\)/);
  const custom = { ...reset, useInherited: false };
  assert.deepEqual(checkboxStates(render(refreshed, custom, true)), [true, false]);
});
const render = (response, intent = valueCodesIntentFromCurrent(response), isPlan = false) =>
  renderToStaticMarkup(React.createElement(ValueCodesProposal, { current: response, intent, isPlan, onChange() {} }));
const checkboxStates = html => [...html.matchAll(/<input\b[^>]*type="checkbox"[^>]*>/g)]
  .map(([tag]) => /checked=""/.test(tag));
const inputs = node => !React.isValidElement(node) ? [] : [
  ...(node.type === "input" ? [node] : []),
  ...React.Children.toArray(node.props.children).flatMap(inputs),
];

test("inherited CBSA and FIPS render checked while the unchanged request remains Default", () => {
  const response = current();
  const intent = valueCodesIntentFromCurrent(response);
  assert.deepEqual(checkboxStates(render(response, intent)), [true, true]);
  assert.match(render(response, intent), /<fieldset disabled=""><legend>Value Code capabilities/);
  assert.match(render(response, intent), /CBSA and FIPS \(inherited\)/);
  assert.match(render(response, intent), /Matches current configuration/);
  assert.equal(valueCodesIntentMatchesCurrent(response, intent), true);
  assert.deepEqual(valueCodesRequestSelections(intent), flags());
});

test("customizing inherited settings starts with their values and sends the changed capabilities", () => {
  const response = current();
  let intent = valueCodesIntentFromCurrent(response);
  const view = () => ValueCodesProposal({ current: response, intent, isPlan: false, onChange: next => { intent = next; } });
  inputs(view()).filter(input => input.props.type === "radio")[1].props.onChange();
  assert.equal(intent.useInherited, false);
  assert.equal(valueCodesIntentMatchesCurrent(response, intent), true, "choosing the same capabilities does not create a needless override");
  inputs(view()).filter(input => input.props.type === "checkbox")[1].props.onChange({ target: { checked: false } });
  assert.deepEqual(valueCodesRequestSelections(intent), flags({ cbsa: true }));
  assert.equal(valueCodesIntentMatchesCurrent(response, intent), false);
  assert.equal(valueCodesIntentIsValid(intent), true);
  assert.deepEqual(checkboxStates(render(response, intent)), [true, false]);
});

test("Default is a separate choice and displays the inherited values instead of the override", () => {
  const response = current({ is_default: false, selections: flags({ cbsa: true }), effective_selections: flags({ cbsa: true }) });
  const custom = valueCodesIntentFromCurrent(response);
  assert.deepEqual(checkboxStates(render(response, custom)), [true, false]);
  const reset = { ...custom, useInherited: true };
  assert.deepEqual(checkboxStates(render(response, reset, true)), [true, true]);
  assert.match(render(response, reset, true), /Customize for this plan/);
  assert.deepEqual(valueCodesRequestSelections(reset), flags());
  assert.equal(valueCodesIntentMatchesCurrent(response, reset), false);
  assert.equal(valueCodesIntentMatchesCurrent(current(), reset), true);
});

test("empty custom choices cannot silently request inheritance or imply Off", () => {
  const intent = { useInherited: false, selections: flags() };
  assert.equal(valueCodesIntentIsValid(intent), false);
  assert.match(render(current(), intent), /Select at least one capability, or choose Use inherited settings/);
  assert.match(render(current(), intent), /No capabilities selected/);
  assert.doesNotMatch(render(current(), intent), /Off \(inherited\)/);
  assert.equal(valueCodesIntentIsValid({ ...intent, useInherited: true }), true);
});

test("minimal-override Apply can confirm requested capabilities that now inherit", () => {
  const requested = { useInherited: false, selections: inherited };
  assert.equal(valueCodesIntentMatchesCurrent(current(), requested), true);
  assert.equal(valueCodesIntentMatchesCurrent(current({ effective_selections: flags({ cbsa: true }) }), requested), false);
  assert.equal(valueCodesIntentMatchesCurrent(current({ effective_selections: null }), requested), false);
  assert.equal(valueCodesIntentMatchesCurrent(current({ is_default: false }), { ...requested, useInherited: true }), false);
});

test("all inherited Hospice combinations use the same checked display without Home Health choices", () => {
  for (const values of [
    { care_location_value_code: true }, { care_location_value_code: true, covered_days_value_code: true },
    { patient_entered_value_code: true }, { patient_entered_value_code: true, covered_days_value_code: true },
    { covered_days_value_code: true },
  ]) {
    const capabilities = flags(values);
    const response = current({ line_of_business: "HOSPICE", effective_selections: capabilities, inherited_selections: capabilities });
    assert.deepEqual(checkboxStates(render(response)), [capabilities.care_location_value_code, capabilities.patient_entered_value_code, capabilities.covered_days_value_code]);
    assert.doesNotMatch(render(response), /Report CBSA|Report FIPS/);
    assert.deepEqual(valueCodesRequestSelections(valueCodesIntentFromCurrent(response)), flags());
  }
});

test("unrecognized inherited settings are unknown, while recognized Off shows unchecked capabilities", () => {
  const unknown = current({ effective_selections: null, inherited_selections: null });
  assert.deepEqual(checkboxStates(render(unknown)), []);
  assert.match(render(unknown), /inherited capabilities cannot be shown individually/);
  assert.doesNotMatch(render(unknown), /Off \(inherited\)/);
  assert.equal(valueCodesDisplayedSelections(unknown, valueCodesIntentFromCurrent(unknown)), null);
  const off = current({ effective_selections: flags(), inherited_selections: flags() });
  assert.deepEqual(checkboxStates(render(off)), [false, false]);
  assert.match(render(off), /Off \(inherited\)/);
});

test("missing effective metadata from an old cached response never renders false disabled claims", () => {
  const response = current({ effective_selections: undefined, inherited_selections: undefined });
  assert.deepEqual(checkboxStates(render(response)), []);
  assert.match(render(response), /inherited capabilities cannot be shown individually/);
});
