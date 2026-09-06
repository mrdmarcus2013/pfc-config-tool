import test from "node:test";
import assert from "node:assert/strict";
import { apiClient } from "../.test-build/api/client.js";
import { CurrentConfigurationCache, currentConfigurationCache } from "../.test-build/app/current-state.js";
import { clearCurrentConfigurations, loadConfigurationOverview, currentBoxSummary, genericCurrentSummary, valueCodesCurrentSummary } from "../.test-build/app/configuration-overview.js";

const context = { payor_guid: "synthetic-payor", plan_guid: null };
test("box summaries describe effective inherited values and conditional addresses", () => {
  assert.equal(valueCodesCurrentSummary({ is_default: true, display_summary: "CBSA and FIPS (inherited)", selections: {} }), "CBSA + FIPS");
  assert.equal(valueCodesCurrentSummary({ is_default: true, display_summary: "Off (inherited)" }), "Off");
  assert.equal(genericCurrentSummary({ capability: "service-facility", display: { mode: "CONDITIONAL", report_address: "Y" } }), "When not HOME · Address included");
  assert.equal(genericCurrentSummary({ capability: "service-facility", display: { mode: "NEVER", report_address: "N" } }), "Off");
  assert.equal(genericCurrentSummary({ capability: "provider-taxonomy", display: { enabled: true } }), "Billing Provider Taxonomy On");
});

test("overview shares editor cache, isolates field errors, and refreshes after apply", async () => {
  clearCurrentConfigurations();
  const original = apiClient.overview;
  let calls = 0;
  apiClient.overview = async () => {
    calls++;
    return { fields: {
      "77": { status: "UNAVAILABLE", error: { category: "ambiguous_source", message: "Unable to resolve" } },
      "81": { status: "RESOLVED", current: { capability: "provider-taxonomy", display: { enabled: false } } },
      "39-41": { status: "RESOLVED", current: { is_default: true, display_summary: "CBSA (inherited)" } },
      "80": { status: "RESOLVED", current: { mode: "CUSTOM", custom_remark: "Synthetic custom remark" } },
    } };
  };
  try {
    assert.equal(currentBoxSummary("remarks", context), "Loading…");
    const overview = loadConfigurationOverview(context);
    const editor = currentConfigurationCache.load({ ...context, field_number: "81" }, () => { throw Error("Duplicate read"); });
    await Promise.all([overview, editor]);
    assert.equal(calls, 1);
    assert.equal(currentBoxSummary("service-facility", context), "Unable to determine");
    assert.equal(currentBoxSummary("provider-taxonomy", context), "Billing Provider Taxonomy Off");
    assert.equal(currentBoxSummary("value-codes", context), "CBSA");
    assert.equal(currentBoxSummary("remarks", context), "Custom Remarks: Synthetic custom remark");
    await currentConfigurationCache.load({ ...context, field_number: "81" }, async () => ({ capability: "provider-taxonomy", display: { enabled: true } }), true);
    assert.equal(currentBoxSummary("provider-taxonomy", context), "Billing Provider Taxonomy On");
    assert.equal(currentBoxSummary("provider-taxonomy", { ...context, plan_guid: "other-plan" }), "Loading…");
  } finally { apiClient.overview = original; clearCurrentConfigurations(); }
});

test("late reads cannot overwrite a refresh or restore a cleared context", async () => {
  const cache = new CurrentConfigurationCache();
  const request = { ...context, field_number: "81" };
  let finish;
  const old = cache.load(request, () => new Promise(resolve => { finish = resolve; }));
  await Promise.resolve();
  await cache.load(request, async () => "new", true);
  finish("old");
  await old;
  assert.deepEqual(cache.peek(request), { status: "ready", current: "new" });
  const stale = cache.load(request, () => new Promise(resolve => { finish = resolve; }), true);
  await Promise.resolve();
  cache.clear();
  finish("stale");
  await stale;
  assert.deepEqual(cache.peek(request), { status: "loading" });
});
