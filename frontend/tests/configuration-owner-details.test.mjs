import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ConfigurationOwnerDetails, configurationSourceStatus } from "../.test-build/app/configuration-owner-details.js";

test("shared owners render once and mixed owners retain every component", () => {
  const shared = { target: "Service facility", level: "USER_TEMPLATE", identifier: "SYN_USER" };
  let html = renderToStaticMarkup(React.createElement(ConfigurationOwnerDetails, {
    owners: [shared, { ...shared, target: "Street address" }],
  }));
  assert.match(html, /Configuration level owner/);
  assert.equal(html.match(/SYN_USER/g).length, 1);
  html = renderToStaticMarkup(React.createElement(ConfigurationOwnerDetails, {
    owners: [shared, { target: "Street address", level: "BILLING_FORM", identifier: "837I_5010" }],
  }));
  assert.match(html, /Multiple owners/);
  assert.match(html, /Street address/);
  assert.match(html, /837I_5010/);
});

test("configuration status follows actual ownership, including payor overrides", () => {
  const owner = (level, target = "Value Codes") => ({ level, target, identifier: "synthetic" });
  assert.equal(configurationSourceStatus([owner("BILLING_FORM")]), "Inherited from billing form code");
  assert.equal(configurationSourceStatus([owner("FORM_TEMPLATE")]), "Inherited from form template");
  assert.equal(configurationSourceStatus([owner("USER_TEMPLATE")]), "Inherited from user template");
  assert.equal(configurationSourceStatus([owner("PAYOR")]), "Payor defined");
  assert.equal(configurationSourceStatus(), "Unavailable");
  assert.equal(configurationSourceStatus([owner("PAYOR", "Service facility"), owner("FORM_TEMPLATE", "Street address")]),
    "Service facility: Payor defined; Street address: Inherited from form template");
});
