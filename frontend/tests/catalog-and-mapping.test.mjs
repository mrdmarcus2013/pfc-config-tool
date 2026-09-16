import test from "node:test";
import assert from "node:assert/strict";
import { CLAIM_FIELD_CATALOG, CLAIM_FIELD_CATALOG_COVERAGE } from "../.test-build/data/claim-field-catalog.js";
import {
  actionLabel, capabilityIsAvailable, catalogFieldIsAvailable, currentPreview,
  previewAfterError, previewAllowsApply,
  previewIdentity, previewRequest, providerTaxonomyOption, serviceFacilityOption,
  SingleFlightGate,
} from "../.test-build/app/workflow.js";
import {
  CurrentConfigurationCache, currentConfigurationKey, currentConfigurationRequest, currentOptionDiffers,
  selectionsFromCurrent,
} from "../.test-build/app/current-state.js";

const serviceOptions = [
  "SERVICE_FACILITY_ALWAYS_ADDRESS_YES", "SERVICE_FACILITY_ALWAYS_ADDRESS_NO",
  "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES", "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO",
  "SERVICE_FACILITY_NEVER",
].map((option_code) => ({ option_code, display_label: option_code }));
const providerOptions = ["PROVIDER_TAXONOMY_ON", "PROVIDER_TAXONOMY_OFF", "PROVIDER_TAXONOMY_CUSTOM"]
  .map((option_code) => ({ option_code, display_label: option_code }));
const optionFields = [
  { field_number: "77", field_label: "Service Facility", options: serviceOptions },
  { field_number: "81", field_label: "Provider Taxonomy", options: providerOptions },
  { field_number: "39-41", field_label: "Value Codes", options: [] },
  { field_number: "80", field_label: "Remarks", options: [] },
];

test("catalog contains every numbered UB-04 locator in standard order", () => {
  assert.equal(CLAIM_FIELD_CATALOG_COVERAGE.complete, true);
  assert.equal(CLAIM_FIELD_CATALOG.length, 159);
  const baseNumbers = new Set(CLAIM_FIELD_CATALOG.map((field) => Number.parseInt(field.fieldNumber, 10)));
  for (let field = 1; field <= 81; field += 1) assert.equal(baseNumbers.has(field), true, `missing ${field}`);
  assert.equal(new Set(CLAIM_FIELD_CATALOG.map((field) => field.id)).size, CLAIM_FIELD_CATALOG.length);
});

test("catalog uses the reviewed Institutional Claim section hierarchy and ranges", () => {
  const expectedSections = [
    ["Billing Details", 1, 7],
    ["Patient", 8, 30],
    ["Admissions & Occurrences", 31, 41],
    ["Services", 42, 49],
    ["Insurance", 50, 65],
    ["Diagnosis & Procedure Codes", 66, 75],
    ["Providers", 76, 79],
    ["Other", 80, 81],
  ];
  assert.deepEqual([...new Set(CLAIM_FIELD_CATALOG.map((field) => field.section))], expectedSections.map(([name]) => name));
  for (const [name, from, through] of expectedSections) {
    const numbers = CLAIM_FIELD_CATALOG
      .filter((field) => field.section === name)
      .map((field) => Number.parseInt(field.fieldNumber, 10));
    assert.equal(Math.min(...numbers), from, `${name} starts at ${from}`);
    assert.equal(Math.max(...numbers), through, `${name} ends at ${through}`);
  }
});

test("catalog preserves standard labels and neutral capabilities", () => {
  assert.equal(CLAIM_FIELD_CATALOG.find((field) => field.fieldNumber === "77")?.label, "Operating Provider");
  assert.equal(CLAIM_FIELD_CATALOG.find((field) => field.fieldNumber === "81")?.label, "cc");
  assert.equal(CLAIM_FIELD_CATALOG.find((field) => field.fieldNumber === "78")?.capabilityKey, null);
  assert.doesNotMatch(JSON.stringify(CLAIM_FIELD_CATALOG), /HER_GUID|RECORD_TYPE_CODE|STO_PROC_NAME|HEF|PACKAGE/i);
});

test("Service Facility selections map to exactly five valid public codes", () => {
  assert.equal(serviceFacilityOption("always", "yes"), "SERVICE_FACILITY_ALWAYS_ADDRESS_YES");
  assert.equal(serviceFacilityOption("always", "no"), "SERVICE_FACILITY_ALWAYS_ADDRESS_NO");
  assert.equal(serviceFacilityOption("conditional", "yes"), "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES");
  assert.equal(serviceFacilityOption("conditional", "no"), "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO");
  assert.equal(serviceFacilityOption("never", "no"), "SERVICE_FACILITY_NEVER");
  assert.equal(serviceFacilityOption("never", "yes"), "SERVICE_FACILITY_NEVER");
  assert.equal(new Set([serviceFacilityOption("always", "yes"), serviceFacilityOption("always", "no"), serviceFacilityOption("conditional", "yes"), serviceFacilityOption("conditional", "no"), serviceFacilityOption("never", "yes")]).size, 5);
});

test("Provider Taxonomy maps Yes and No", () => {
  assert.equal(providerTaxonomyOption("yes"), "PROVIDER_TAXONOMY_ON");
  assert.equal(providerTaxonomyOption("no"), "PROVIDER_TAXONOMY_OFF");
});

test("API metadata activates only complete supported capabilities", () => {
  assert.equal(capabilityIsAvailable("service-facility", optionFields), true);
  assert.equal(capabilityIsAvailable("provider-taxonomy", optionFields), true);
  assert.equal(capabilityIsAvailable("service-facility", [{ ...optionFields[0], options: serviceOptions.slice(1) }]), false);
  assert.equal(capabilityIsAvailable("provider-taxonomy", []), false);
  assert.equal(capabilityIsAvailable("value-codes", optionFields), true);
  assert.equal(capabilityIsAvailable("remarks", optionFields), true);
  assert.equal(catalogFieldIsAvailable(CLAIM_FIELD_CATALOG.find((field) => field.fieldNumber === "77"), optionFields), true);
  assert.equal(catalogFieldIsAvailable(CLAIM_FIELD_CATALOG.find((field) => field.fieldNumber === "78"), optionFields), false);
});

test("technical target actions have safe user-facing translations", () => {
  assert.equal(actionLabel("NO_CHANGE"), "Already configured as requested");
  assert.equal(actionLabel("REBUILD_OVERRIDE"), "Configuration will be updated");
  assert.equal(actionLabel("REMOVE_OVERRIDE"), "Existing payor-specific customization will be removed");
  assert.equal(actionLabel("BLOCKED"), "Configuration cannot be changed");
});

test("preview identity invalidates on option, payor, or plan change", () => {
  const context = { payor_guid: "payor", plan_guid: null, pfc_guid: "pfc", audit_user: "audit" };
  const option = providerTaxonomyOption("no");
  const identity = previewIdentity(context, option);
  const record = { identity, response: { state_hash: "HASH" } };
  assert.deepEqual(currentPreview(record, identity), { state_hash: "HASH" });
  assert.equal(currentPreview(record, previewIdentity(context, providerTaxonomyOption("yes"))), null);
  assert.equal(currentPreview(record, previewIdentity({ ...context, plan_guid: "plan" }, option)), null);
  assert.equal(currentPreview(record, previewIdentity({ ...context, payor_guid: "other" }, option)), null);
});

test("preview/apply gating handles NO_CHANGE, blocked, stale, and double submit", () => {
  const base = { status: "PREVIEW", change_count: 1, debug_changes: [], state_hash: "HASH" };
  assert.equal(previewAllowsApply(null), false);
  assert.equal(previewAllowsApply({ ...base, status: "NO_CHANGE", change_count: 0 }), false);
  assert.equal(previewAllowsApply({ ...base, debug_changes: [{ operation_code: "BLOCKED" }] }), false);
  assert.equal(previewAllowsApply(base), true);
  assert.equal(previewAfterError({ state_hash: "HASH" }, "stale_preview"), null);
  assert.deepEqual(previewAfterError({ state_hash: "HASH" }, "server_failure"), { state_hash: "HASH" });
  const gate = new SingleFlightGate();
  assert.equal(gate.tryEnter(), true);
  assert.equal(gate.tryEnter(), false);
  gate.exit();
  assert.equal(gate.tryEnter(), true);
});

test("preview request uses launch context without trusting display PFC", () => {
  const context = { payor_guid: "payor", plan_guid: "plan", pfc_guid: "display-pfc", audit_user: "audit" };
  assert.deepEqual(previewRequest(context, providerTaxonomyOption("yes")), {
    payor_guid: "payor", plan_guid: "plan", option_code: "PROVIDER_TAXONOMY_ON", audit_user: "audit",
  });
});

const currentResponse = (effective_option_code, overrides = {}) => ({
  status: "RESOLVED",
  field_number: effective_option_code.startsWith("SERVICE") ? "77" : "81",
  capability: effective_option_code.startsWith("SERVICE") ? "service-facility" : "provider-taxonomy",
  effective_option_code,
  display: { mode: null, report_address: null, enabled: null },
  pfc_guid: "synthetic-pfc",
  canonical: true,
  ...overrides,
});

test("current configuration initializes every supported control state", () => {
  assert.deepEqual(selectionsFromCurrent(currentResponse("SERVICE_FACILITY_ALWAYS_ADDRESS_YES")), {
    serviceMode: "always", serviceAddress: "yes", taxonomy: "no",
  });
  assert.deepEqual(selectionsFromCurrent(currentResponse("SERVICE_FACILITY_ALWAYS_ADDRESS_NO")), {
    serviceMode: "always", serviceAddress: "no", taxonomy: "no",
  });
  assert.deepEqual(selectionsFromCurrent(currentResponse("SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES")), {
    serviceMode: "conditional", serviceAddress: "yes", taxonomy: "no",
  });
  assert.deepEqual(selectionsFromCurrent(currentResponse("SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO")), {
    serviceMode: "conditional", serviceAddress: "no", taxonomy: "no",
  });
  assert.deepEqual(selectionsFromCurrent(currentResponse("SERVICE_FACILITY_NEVER")), {
    serviceMode: "never", serviceAddress: "no", taxonomy: "no",
  });
  assert.equal(selectionsFromCurrent(currentResponse("PROVIDER_TAXONOMY_ON")).taxonomy, "yes");
  assert.equal(selectionsFromCurrent(currentResponse("PROVIDER_TAXONOMY_OFF")).taxonomy, "no");
});

test("proposed state becomes dirty on change and clean when changed back", () => {
  const current = currentResponse("PROVIDER_TAXONOMY_OFF");
  assert.equal(currentOptionDiffers(current, "PROVIDER_TAXONOMY_ON"), true);
  assert.equal(currentOptionDiffers(current, "PROVIDER_TAXONOMY_OFF"), false);
  assert.equal(currentOptionDiffers(null, "PROVIDER_TAXONOMY_OFF"), false);
});

test("current configuration cache keys by context, coalesces loads, and invalidates after apply", async () => {
  const context = { payor_guid: "synthetic-payor", plan_guid: null, pfc_guid: "display", audit_user: "synthetic-audit" };
  const request = currentConfigurationRequest(context, "81");
  assert.deepEqual(request, { payor_guid: "synthetic-payor", plan_guid: null, field_number: "81" });
  assert.equal(currentConfigurationKey(request), "synthetic-payor||81");

  const cache = new CurrentConfigurationCache();
  let calls = 0;
  const loader = async () => { calls += 1; return currentResponse("PROVIDER_TAXONOMY_OFF"); };
  const [first, concurrent] = await Promise.all([cache.load(request, loader), cache.load(request, loader)]);
  assert.equal(first.effective_option_code, "PROVIDER_TAXONOMY_OFF");
  assert.equal(concurrent, first);
  assert.equal(calls, 1);
  assert.equal(await cache.load(request, loader), first);
  assert.equal(calls, 1);

  cache.invalidate(request);
  await cache.load(request, loader);
  assert.equal(calls, 2);
  await cache.load(request, loader, true);
  assert.equal(calls, 3);

  cache.clear();
  await cache.load(request, loader);
  assert.equal(calls, 4);
});
