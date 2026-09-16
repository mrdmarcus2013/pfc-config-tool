import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { PreviewResult } from "../.test-build/app/preview-result.js";
import {
  SUPPORT_DEVELOPER_MODE, technicalDetailsEnabled, technicalDetailsEnabledFromEnvironment,
} from "../.test-build/app/environment.js";
import {
  fieldEditorTitle, supportPreviewPresentation,
} from "../.test-build/app/presentation.js";
import { CLAIM_FIELD_CATALOG } from "../.test-build/data/claim-field-catalog.js";

const frontendRoot = dirname(dirname(fileURLToPath(import.meta.url)));

const previewResponse = (overrides = {}) => ({
  status: "PREVIEW",
  option_code: "PROVIDER_TAXONOMY_ON",
  display_label: "Provider Taxonomy ON",
  field_number: "81",
  state_hash: "SYNTHETIC_STATE_HASH",
  change_count: 1,
  summary: "Generic API summary retained for diagnostics",
  pfc_guid: "00000000-0000-0000-0000-000000000081",
  debug_changes: [{
    operation_order: 1,
    operation_code: "SET_HEF_VALUE",
    target_identifier: "SYNTHETIC_TARGET",
    field_number: "81",
  }],
  ...overrides,
});

test("catalog and editor use the reviewed Field 81 cc label", () => {
  const field = CLAIM_FIELD_CATALOG.find((candidate) => candidate.fieldNumber === "81");
  assert.equal(field?.label, "cc");
  assert.equal(fieldEditorTitle(field), "Field 81cc");
});

test("technical details default off and can be enabled only by the support flag", () => {
  assert.equal(technicalDetailsEnabled(undefined), false);
  assert.equal(technicalDetailsEnabled(false), false);
  assert.equal(technicalDetailsEnabled("false"), false);
  assert.equal(technicalDetailsEnabled("true"), true);
  assert.equal(technicalDetailsEnabled("TRUE"), true);
});

test("missing environment object and optional flag safely default to disabled", () => {
  assert.equal(technicalDetailsEnabledFromEnvironment(undefined), false);
  assert.equal(technicalDetailsEnabledFromEnvironment({}), false);
  assert.equal(technicalDetailsEnabledFromEnvironment({ VITE_ENABLE_TECHNICAL_DETAILS: undefined }), false);
  assert.equal(technicalDetailsEnabledFromEnvironment({ VITE_ENABLE_TECHNICAL_DETAILS: "" }), false);
  assert.equal(technicalDetailsEnabledFromEnvironment({ VITE_ENABLE_TECHNICAL_DETAILS: "false" }), false);
  assert.equal(technicalDetailsEnabledFromEnvironment({ VITE_ENABLE_TECHNICAL_DETAILS: "anything-else" }), false);
  assert.equal(SUPPORT_DEVELOPER_MODE, false);
});

test("explicit Vite true value enables Tier-2 diagnostics", () => {
  assert.equal(technicalDetailsEnabledFromEnvironment({
    VITE_ENABLE_TECHNICAL_DETAILS: "true",
  }), true);
});

test("normal application startup does not directly dereference import.meta.env", () => {
  const source = readFileSync(join(frontendRoot, "src", "App.tsx"), "utf8");
  assert.doesNotMatch(source, /import\.meta\.env/);
  assert.match(source, /SUPPORT_DEVELOPER_MODE/);
  assert.equal(SUPPORT_DEVELOPER_MODE, false);
});

test("payor and plan switching is available while diagnostics remain gated", () => {
  const source = readFileSync(join(frontendRoot, "src", "App.tsx"), "utf8");
  assert.match(source, /<ContextSelectors/);
  assert.match(source, /SUPPORT_DEVELOPER_MODE && <details/);
  assert.match(source, /clearCurrentConfigurations\(\)/);
  assert.match(source, /contextRequestSequence/);
});

test("normal preview hides diagnostics while support mode renders retained technical data", () => {
  const preview = previewResponse();
  const retainedChanges = structuredClone(preview.debug_changes);
  const normal = renderToStaticMarkup(React.createElement(PreviewResult, {
    optionCode: "PROVIDER_TAXONOMY_ON", preview, supportDeveloperMode: false,
  }));
  assert.doesNotMatch(normal, /Technical details|SET_HEF_VALUE|SYNTHETIC_STATE_HASH/);
  assert.match(normal, />Preview</);
  assert.deepEqual(preview.debug_changes, retainedChanges);

  const support = renderToStaticMarkup(React.createElement(PreviewResult, {
    optionCode: "PROVIDER_TAXONOMY_ON", preview, supportDeveloperMode: true,
  }));
  assert.match(support, /Technical details/);
  assert.match(support, /SET_HEF_VALUE/);
  assert.match(support, /SYNTHETIC_TARGET/);
  assert.match(support, /SYNTHETIC_STATE_HASH/);
  assert.match(support, /Generic API summary retained for diagnostics/);
});

test("NO_CHANGE preview explicitly says the request is already configured and performs no database changes", () => {
  const markup = renderToStaticMarkup(React.createElement(PreviewResult, {
    optionCode: "PROVIDER_TAXONOMY_ON",
    preview: previewResponse({ status: "NO_CHANGE", change_count: 0, debug_changes: [] }),
    supportDeveloperMode: false,
  }));
  assert.match(markup, /Already configured/);
  assert.match(markup, /matches the current effective configuration/);
  assert.match(markup, /No database changes are required/);
  assert.doesNotMatch(markup, /Technical details/);
});

test("Provider Taxonomy ON, OFF, and NO_CHANGE summaries are support-friendly", () => {
  const on = supportPreviewPresentation("PROVIDER_TAXONOMY_ON", previewResponse());
  assert.equal(on.requestedConfiguration[0].value, "Standard");
  assert.match(on.message, /will be enabled for this payor/);
  assert.deepEqual(on.changes, ["Provider Taxonomy configuration will be updated."]);

  const off = supportPreviewPresentation("PROVIDER_TAXONOMY_OFF", previewResponse({ option_code: "PROVIDER_TAXONOMY_OFF" }));
  assert.equal(off.requestedConfiguration[0].value, "None");
  assert.match(off.message, /will be disabled for this payor/);

  const noChange = supportPreviewPresentation("PROVIDER_TAXONOMY_ON", previewResponse({ status: "NO_CHANGE", change_count: 0, debug_changes: [] }));
  assert.equal(noChange.statusLabel, "Already configured");
  assert.equal(noChange.heading, "Already configured");
  assert.equal(noChange.message, "The requested configuration matches the current effective configuration.");
  assert.deepEqual(noChange.changes, []);
});

test("Service Facility Always summaries distinguish address Yes and No", () => {
  const yes = supportPreviewPresentation("SERVICE_FACILITY_ALWAYS_ADDRESS_YES", previewResponse());
  assert.deepEqual(yes.requestedConfiguration, [
    { label: "Service Facility Reporting", value: "Always report service facility" },
    { label: "Report address", value: "Yes" },
  ]);
  assert.match(yes.changes.join(" "), /address reporting will be enabled/);

  const no = supportPreviewPresentation("SERVICE_FACILITY_ALWAYS_ADDRESS_NO", previewResponse());
  assert.equal(no.requestedConfiguration[1].value, "No");
  assert.match(no.changes.join(" "), /address reporting will be disabled/);
  assert.doesNotMatch(no.changes.join(" "), /address reporting will be enabled/);
});

test("Service Facility Conditional, Never, and NO_CHANGE wording is explicit", () => {
  const conditional = supportPreviewPresentation("SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES", previewResponse());
  assert.equal(conditional.requestedConfiguration[0].value, "Only report service facility when care location is not HOME");
  assert.match(conditional.message, /only when care location is not HOME/);

  const never = supportPreviewPresentation("SERVICE_FACILITY_NEVER", previewResponse());
  assert.equal(never.requestedConfiguration[0].value, "Never report service facility");
  assert.equal(never.requestedConfiguration[1].value, "No");
  assert.match(never.message, /will be disabled for this payor/);
  assert.doesNotMatch(never.changes.join(" "), /enabled/);

  const noChange = supportPreviewPresentation("SERVICE_FACILITY_ALWAYS_ADDRESS_YES", previewResponse({ status: "NO_CHANGE", change_count: 0, debug_changes: [] }));
  assert.equal(noChange.statusLabel, "Already configured");
  assert.equal(noChange.message, "The requested configuration matches the current effective configuration.");
  assert.equal(noChange.heading, "Already configured");
  assert.deepEqual(noChange.changes, []);
});
