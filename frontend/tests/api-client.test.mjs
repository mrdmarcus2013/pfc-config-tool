import test from "node:test";
import assert from "node:assert/strict";
import { apiClient, ApiClientError } from "../.test-build/api/client.js";
import { safeError } from "../.test-build/app/workflow.js";

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

test("Provider preview sends one exact launch-context request", async () => {
  const calls = [];
  globalThis.fetch = async (path, init) => { calls.push({ path, init }); return jsonResponse({ status: "PREVIEW" }); };
  const request = { payor_guid: "payor", plan_guid: null, option_code: "PROVIDER_TAXONOMY_ON", audit_user: "audit" };
  await apiClient.preview(request);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].path, "/api/config/preview");
  assert.deepEqual(JSON.parse(calls[0].init.body), request);
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

test("metadata failure and backend unavailability are safe", async () => {
  globalThis.fetch = async () => jsonResponse({ error: { category: "stale_preview", message: "ORA-20504 raw text" } }, 409);
  await assert.rejects(apiClient.options(), (error) => error instanceof ApiClientError && error.category === "stale_preview");
  assert.equal(safeError(new ApiClientError("stale_preview", "ORA-20504 raw text", 409)).message, "Configuration changed since the preview.");
  assert.doesNotMatch(safeError(new Error("ORA-00942 raw text")).message, /ORA-/);
  globalThis.fetch = async () => { throw new Error("network details"); };
  await assert.rejects(apiClient.options(), /configuration service is unavailable/i);
});
