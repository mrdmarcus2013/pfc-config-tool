import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import {
  launchContextFromResolvedSelection,
  payorContextKey,
  payorContextLabel,
} from "../.test-build/app/payor-context.js";
import { PayorContextSelector } from "../.test-build/app/payor-context-selector.js";

const payorOne = {
  payor_guid: "payor-1",
  payor_name: "Synthetic Payor One",
  payor_id: "SYN-ONE",
  plan_guid: null,
};
const payorTwo = {
  payor_guid: "payor-2",
  payor_name: "Synthetic Payor Two",
  payor_id: "SYN-TWO",
  plan_guid: "plan-2",
};

test("payor selection keys and labels keep each plan attached to its payor", () => {
  assert.notEqual(payorContextKey(payorOne), payorContextKey(payorTwo));
  assert.equal(
    payorContextLabel(payorOne),
    "Synthetic Payor One (SYN-ONE) — No plan",
  );
  assert.equal(
    payorContextLabel(payorTwo),
    "Synthetic Payor Two (SYN-TWO) — Plan plan-2",
  );
});

test("resolved selection creates one linked active context and preserves audit identity", () => {
  const active = launchContextFromResolvedSelection(payorTwo, {
    status: "RESOLVED",
    payor_guid: "payor-2",
    plan_guid: "plan-2",
    pfc_guid: "pfc-2",
    billing_form_code: "837I_5010",
    form_template_guid: "form-2",
    user_form_template_guid: "user-2",
  }, "tier-2-user");

  assert.deepEqual(active, {
    payor_guid: "payor-2",
    plan_guid: "plan-2",
    pfc_guid: "pfc-2",
    audit_user: "tier-2-user",
  });
  assert.throws(
    () => launchContextFromResolvedSelection(
      payorOne,
      { status: "RESOLVED", payor_guid: "different-payor", plan_guid: null,
        pfc_guid: "wrong-pfc", billing_form_code: "837I_5010",
        form_template_guid: null, user_form_template_guid: null },
      "tier-2-user",
    ),
    /did not match/,
  );
});

test("Tier 2 selector renders linked options and disables itself while switching", () => {
  const markup = renderToStaticMarkup(React.createElement(PayorContextSelector, {
    contexts: [payorOne, payorTwo],
    activeContext: payorOne,
    loading: false,
    switching: true,
    error: null,
    onSelect: () => {},
  }));

  assert.match(markup, /Tier 2 support/);
  assert.match(markup, /Select payor/);
  assert.match(markup, /Synthetic Payor One \(SYN-ONE\).*No plan/);
  assert.match(markup, /Synthetic Payor Two \(SYN-TWO\).*Plan plan-2/);
  assert.match(markup, /<select[^>]*disabled/);
  assert.match(markup, /Resolving the selected payor/);
  assert.doesNotMatch(markup, /form-2|user-2|wrong-pfc/);
});
