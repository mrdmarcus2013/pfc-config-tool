import test, { afterEach } from "node:test";
import assert from "node:assert/strict";
import { apiClient, ApiClientError } from "../.test-build/api/client.js";
import { safeError } from "../.test-build/app/workflow.js";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });

const jsonResponse = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json" },
});

test("options metadata uses the actual endpoint", async () => {
  const calls = [];
  globalThis.fetch = async (...args) => { calls.push(args); return jsonResponse({ fields: [] }); };
  assert.deepEqual(await apiClient.options(), { fields: [] });
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "/api/options");
});

test("Tier 2 payor catalog uses the read-only support endpoint", async () => {
  const calls = [];
  globalThis.fetch = async (...args) => {
    calls.push(args);
    return jsonResponse({ contexts: [] });
  };

  assert.deepEqual(await apiClient.supportPayorContexts(), { contexts: [] });
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "/api/support/payor-contexts");
  assert.equal(calls[0][1], undefined);
});

test("Provider preview sends one exact launch-context request", async () => {
  const calls = [];
  globalThis.fetch = async (path, init) => { calls.push({ path, init }); return jsonResponse({ status: "PREVIEW" }); };
  const request = { payor_guid: "payor", plan_guid: null, option_code: "PROVIDER_TAXONOMY_ON", audit_user: "audit" };
  await apiClient.preview(request);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].path, "/api/config/preview");
  assert.deepEqual(JSON.parse(calls[0].init.body), request);
});

test("Tier 2 configuration context requests the resolved PFC and templates", async () => {
  const calls = [];
  globalThis.fetch = async (path, init) => {
    calls.push({ path, init });
    return jsonResponse({ status: "RESOLVED" });
  };
  const request = { payor_guid: "synthetic-payor", plan_guid: "synthetic-plan" };

  await apiClient.configurationContext(request);

  assert.equal(calls.length, 1);
  assert.equal(calls[0].path, "/api/config/context");
  assert.equal(calls[0].init.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].init.body), request);
  assert.doesNotMatch(calls[0].init.body, /audit/i);
});

test("opening each supported field uses one current-state request without audit data", async () => {
  const calls = [];
  globalThis.fetch = async (path, init) => {
    calls.push({ path, init });
    return jsonResponse({ status: "RESOLVED" });
  };
  const providerRequest = { payor_guid: "synthetic-payor", plan_guid: null, field_number: "81" };
  const serviceRequest = { payor_guid: "synthetic-payor", plan_guid: null, field_number: "77" };
  await apiClient.current(providerRequest);
  await apiClient.current(serviceRequest);
  assert.equal(calls.length, 2);
  assert.equal(calls.filter((call) => call.path === "/api/config/current").length, 2);
  assert.equal(calls[0].init.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].init.body), providerRequest);
  assert.deepEqual(JSON.parse(calls[1].init.body), serviceRequest);
  assert.doesNotMatch(calls.map((call) => call.init.body).join(" "), /audit/i);
});

test("Service Facility preview and apply each make one request and forward the hash", async () => {
  const calls = [];
  globalThis.fetch = async (path, init) => { calls.push({ path, body: JSON.parse(init.body) }); return jsonResponse({ status: "PREVIEW" }); };
  const base = { payor_guid: "payor", plan_guid: "plan", option_code: "SERVICE_FACILITY_ALWAYS_ADDRESS_YES", audit_user: "audit" };
  await apiClient.preview(base);
  await apiClient.apply({ ...base, expected_state_hash: "A".repeat(64) });
  assert.equal(calls.length, 2);
  assert.equal(calls.filter((call) => call.path === "/api/config/preview").length, 1);
  assert.equal(calls.filter((call) => call.path === "/api/config/apply").length, 1);
  assert.equal(calls[1].body.expected_state_hash, "A".repeat(64));
  assert.equal(calls[1].body.option_code, "SERVICE_FACILITY_ALWAYS_ADDRESS_YES");
});

test("Line of Business uses payor-level current/save and exact preview hash apply", async () => {
  const calls = [];
  globalThis.fetch = async (path, init) => {
    calls.push({ path, body: JSON.parse(init.body) });
    return jsonResponse(path.endsWith("current")
      ? { status: "UNDEFINED", line_of_business: null }
      : { status: "SAVED", line_of_business: "HOME_HEALTH" });
  };
  await apiClient.lineOfBusinessCurrent({ payor_guid: "synthetic-payor" });
  await apiClient.lineOfBusinessSave({
    payor_guid: "synthetic-payor", line_of_business: "HOME_HEALTH", audit_user: "synthetic-audit",
  });
  await apiClient.lineOfBusinessPreviewChange({
    payor_guid: "synthetic-payor", requested_line_of_business: "HOSPICE",
  });
  await apiClient.lineOfBusinessApplyChange({
    payor_guid: "synthetic-payor", requested_line_of_business: "HOSPICE",
    expected_state_hash: "C".repeat(64), audit_user: "synthetic-audit",
  });
  assert.deepEqual(calls.map((call) => call.path), [
    "/api/config/line-of-business/current",
    "/api/config/line-of-business/save",
    "/api/config/line-of-business/preview-change",
    "/api/config/line-of-business/apply-change",
  ]);
  assert.deepEqual(calls[0].body, { payor_guid: "synthetic-payor" });
  assert.equal(calls[3].body.expected_state_hash, "C".repeat(64));
  assert.equal("plan_guid" in calls[3].body, false);
  assert.equal("pfc_guid" in calls[3].body, false);
});

test("Value Codes uses separate structured endpoints and forwards the preview hash", async () => {
  const calls = [];
  globalThis.fetch = async (path, init) => {
    calls.push({ path, body: JSON.parse(init.body) });
    return jsonResponse({ status: "PREVIEW" });
  };
  const selections = { cbsa: true, fips: false,
    care_location_value_code: false, patient_entered_value_code: false,
    covered_days_value_code: false };
  const base = { payor_guid: "payor", plan_guid: null, selections, audit_user: "audit" };
  await apiClient.valueCodesCurrent({ payor_guid: "payor", plan_guid: null });
  await apiClient.valueCodesPreview(base);
  await apiClient.valueCodesApply({ ...base, expected_state_hash: "E".repeat(64) });
  assert.deepEqual(calls.map((call) => call.path), [
    "/api/config/value-codes/current", "/api/config/value-codes/preview",
    "/api/config/value-codes/apply",
  ]);
  assert.deepEqual(calls[1].body.selections, selections);
  assert.equal(calls[2].body.expected_state_hash, "E".repeat(64));
  assert.equal("option_code" in calls[2].body, false);
});

test("metadata failure and backend unavailability are safe", async () => {
  globalThis.fetch = async () => jsonResponse({ error: { category: "stale_preview", message: "ORA-20504 raw text" } }, 409);
  await assert.rejects(apiClient.options(), (error) => error instanceof ApiClientError && error.category === "stale_preview");
  assert.equal(safeError(new ApiClientError("stale_preview", "ORA-20504 raw text", 409)).message, "Configuration changed since the preview.");
  assert.doesNotMatch(safeError(new Error("ORA-00942 raw text")).message, /ORA-/);
  globalThis.fetch = async () => { throw new Error("network details"); };
  await assert.rejects(apiClient.options(), /configuration service is unavailable/i);
});

test("Value Codes preserves explicit Off and legacy inheritance semantics through Preview and Apply", async () => {
  const calls = [];
  globalThis.fetch = async (path, init) => {
    calls.push({ path, body: JSON.parse(init.body) });
    return jsonResponse({ status: "PREVIEW" });
  };
  const selections = { cbsa: false, fips: false, care_location_value_code: false,
    patient_entered_value_code: false, covered_days_value_code: false };
  const base = { payor_guid: "synthetic-payor", plan_guid: "synthetic-plan", selections, audit_user: "synthetic-audit" };
  const explicit = { ...base, empty_selection_behavior: "OFF" };
  await apiClient.valueCodesPreview(explicit);
  await apiClient.valueCodesApply({ ...explicit, expected_state_hash: "F".repeat(64) });
  await apiClient.valueCodesPreview(base);
  await apiClient.valueCodesPreview({ ...base, empty_selection_behavior: "INHERIT" });
  assert.deepEqual(calls[0], { path: "/api/config/value-codes/preview", body: explicit });
  assert.deepEqual(calls[1], { path: "/api/config/value-codes/apply", body: { ...explicit, expected_state_hash: "F".repeat(64) } });
  assert.equal("empty_selection_behavior" in calls[2].body, false, "omitted legacy behavior must remain omitted");
  assert.equal(calls[3].body.empty_selection_behavior, "INHERIT");
  assert.deepEqual(calls.map(call => call.body.selections), [selections, selections, selections, selections]);
});
