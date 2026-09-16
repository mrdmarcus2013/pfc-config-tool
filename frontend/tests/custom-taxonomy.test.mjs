import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { TaxonomyControls, normalizeTaxonomyCode, validTaxonomyCode } from "../.test-build/app/taxonomy-controls.js";
import { previewIdentity, previewRequest } from "../.test-build/app/workflow.js";
import { currentOptionDiffers, selectionsFromCurrent } from "../.test-build/app/current-state.js";
import { supportPreviewPresentation } from "../.test-build/app/presentation.js";
import { genericCurrentSummary } from "../.test-build/app/configuration-overview.js";

const context = { payor_guid: "SYN-PAYOR", plan_guid: null, audit_user: "SYN-AUDIT" };
const option = "PROVIDER_TAXONOMY_CUSTOM";
const current = { capability: "provider-taxonomy", effective_option_code: option,
  display: { enabled: true, taxonomy_code: "SYN000000A" } };

test("custom taxonomy is required, limited to ten characters, and only shown for Custom", () => {
  for (const selection of ["no", "yes", "custom"]) {
    const markup = renderToStaticMarkup(React.createElement(TaxonomyControls, {
      selection, code: "SYN000000A", busy: false, onSelection() {}, onCode() {},
    }));
    assert.match(markup, />None</);
    assert.match(markup, />Standard</);
    assert.match(markup, />Custom</);
    if (selection === "custom") {
      assert.match(markup, /maxLength="10"/);
      assert.match(markup, /required=""/);
      assert.match(markup, /value="SYN000000A"/);
      assert.match(markup, /aria-invalid="false"/);
    } else assert.doesNotMatch(markup, /id="taxonomy-code"/);
  }
  assert.equal(normalizeTaxonomyCode(" syn000000a "), "SYN000000A");
  for (const value of ["", "SYN000000", "SYN000000AA", "SYN000000!", "SYN 00000A", "é123456789"]) {
    assert.equal(validTaxonomyCode(value), false);
  }
});

test("custom code participates in dirty state, refreshed-state confirmation, and preview identity", () => {
  assert.equal(selectionsFromCurrent(current).taxonomy, "custom");
  assert.equal(currentOptionDiffers(current, option, "SYN000000A"), false);
  assert.equal(currentOptionDiffers(current, option, "SYN000000B"), true);
  assert.notEqual(previewIdentity(context, option, "SYN000000A"), previewIdentity(context, option, "SYN000000B"));
  assert.equal(previewRequest(context, option, "SYN000000A").taxonomy_code, "SYN000000A");
  assert.equal("taxonomy_code" in previewRequest(context, "PROVIDER_TAXONOMY_ON", "SYN000000A"), false);
  assert.equal("taxonomy_code" in previewRequest(context, "PROVIDER_TAXONOMY_OFF", "SYN000000A"), false);
});

test("custom code appears in overview and preview without technical details", () => {
  assert.equal(genericCurrentSummary(current), "Billing Provider Taxonomy Custom: SYN000000A");
  const presentation = supportPreviewPresentation(option, {
    status: "PREVIEW", taxonomy_code: "SYN000000A", debug_changes: [],
  });
  assert.equal(presentation.requestedConfiguration[0].value, "Custom: SYN000000A");
  assert.match(presentation.message, /enabled/);
});
