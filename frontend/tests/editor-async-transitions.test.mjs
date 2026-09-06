import test from "node:test";
import assert from "node:assert/strict";
import { CurrentConfigurationCache } from "../.test-build/app/current-state.js";
import {
  currentPreview, previewAllowsApply, previewIdentity,
} from "../.test-build/app/workflow.js";

const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const context = { payor_guid: "synthetic-payor", plan_guid: null, audit_user: "synthetic-audit" };
const ready = { status: "PREVIEW", change_count: 1, debug_changes: [], state_hash: "SYNTHETIC_HASH" };

test("a delayed preview remains bound to its original payor, plan, and proposal", async () => {
  const response = deferred();
  const identity = previewIdentity(context, "PROVIDER_TAXONOMY_ON");
  const record = response.promise.then(value => ({ identity, response: value }));
  response.resolve(ready);
  const completed = await record;
  assert.equal(previewAllowsApply(currentPreview(completed, identity)), true);
  for (const changed of [
    previewIdentity(context, "PROVIDER_TAXONOMY_OFF"),
    previewIdentity({ ...context, plan_guid: "synthetic-plan" }, "PROVIDER_TAXONOMY_ON"),
    previewIdentity({ ...context, payor_guid: "synthetic-other" }, "PROVIDER_TAXONOMY_ON"),
  ]) assert.equal(previewAllowsApply(currentPreview(completed, changed)), false);
});

test("a failed current read can retry without retaining its error or old value", async () => {
  const cache = new CurrentConfigurationCache();
  const request = { ...context, field_number: "81" };
  const first = deferred();
  const failed = cache.load(request, () => first.promise);
  const rejection = assert.rejects(failed, /synthetic read failed/);
  first.reject(new Error("synthetic read failed"));
  await rejection;
  assert.deepEqual(cache.peek(request), { status: "error" });
  const retry = deferred();
  const retried = cache.load(request, () => retry.promise);
  assert.deepEqual(cache.peek(request), { status: "loading" });
  retry.resolve({ effective_option_code: "PROVIDER_TAXONOMY_ON" });
  const result = await retried;
  assert.deepEqual(cache.peek(request), { status: "ready", current: result });
});

test("a late failure from an invalidated current read cannot replace a successful refresh", async () => {
  const cache = new CurrentConfigurationCache();
  const request = { ...context, field_number: "81" };
  const old = deferred();
  const first = cache.load(request, () => old.promise);
  const rejection = assert.rejects(first, /old request/);
  const refreshed = await cache.load(request, async () => "refreshed", true);
  old.reject(new Error("old request"));
  await rejection;
  assert.deepEqual(cache.peek(request), { status: "ready", current: refreshed });
});
