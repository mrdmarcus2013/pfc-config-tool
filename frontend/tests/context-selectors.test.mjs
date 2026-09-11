import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ContextSelectors } from "../.test-build/app/context-selectors.js";
import { launchContextFromResolvedSelection } from "../.test-build/app/payor-context.js";

const base = { payor_guid: "p1", payor_name: "First payor", payor_id: "SYN-1", plan_guid: null };
test("header orders payor, owned plans and billing form and hides foreign plans", () => {
  const markup = renderToStaticMarkup(React.createElement(ContextSelectors, {
    contexts: [base, { ...base, plan_guid: "plan1", plan_name: "Owned plan" },
      { ...base, payor_guid: "p2", payor_name: "Second payor", plan_guid: "foreign", plan_name: "Foreign plan" }],
    active: base, disabled: false, billingForm: "837I_5010", onSelect() {},
  }));
  assert.ok(markup.indexOf('context-payor') < markup.indexOf('context-plan'));
  assert.ok(markup.indexOf('context-plan') < markup.indexOf('Billing Form'));
  assert.match(markup, /All Plans/);
  assert.match(markup, /Owned plan/);
  assert.match(markup, /Second payor/);
  assert.doesNotMatch(markup, /Foreign plan|foreign/);
});

test("resolved context cannot substitute a different plan or no-plan fallback", () => {
  assert.throws(() => launchContextFromResolvedSelection({ ...base, plan_guid: "plan1" },
    { payor_guid: "p1", plan_guid: null, pfc_guid: "pfc1" }, "synthetic-audit"), /did not match/);
});
