import test from "node:test";
import assert from "node:assert/strict";
import { apiClient, ApiClientError } from "../.test-build/api/client.js";
import { readCurrentLineOfBusiness } from "../.test-build/app/line-of-business-current.js";
import {
  LineOfBusinessRequestScope, runLineOfBusinessRequest,
} from "../.test-build/app/line-of-business-request.js";
import {
  clearCurrentConfigurations, remarksCurrentCache, valueCodesCurrentCache,
} from "../.test-build/app/configuration-overview.js";
import { currentConfigurationCache } from "../.test-build/app/current-state.js";

const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const flush = () => new Promise(resolve => setImmediate(resolve));
const caches = [currentConfigurationCache, valueCodesCurrentCache, remarksCurrentCache];
const cachedRequest = { payor_guid: "SYN-A", plan_guid: "SYN-PLAN", field_number: "81" };

function control(scope = new LineOfBusinessRequestScope()) {
  const unmount = scope.activate();
  const state = { busy: null, error: null, response: null, saved: 0 };
  const events = [];
  const options = {
    scope,
    setBusy(value) { state.busy = value; events.push(["busy", value]); },
    setError(value) { state.error = value; events.push(["error", value]); },
    onSuccess(value) { state.response = value; events.push(["success", value]); },
    onSaved() { state.saved++; events.push(["saved"]); },
  };
  return { scope, unmount, state, events, options };
}

test("active LOB save, Preview, and Apply preserve responses and prevent duplicate requests", async () => {
  for (const operation of ["save", "preview", "apply"]) {
    clearCurrentConfigurations();
    for (const cache of caches) await cache.load(cachedRequest, async () => "cached");
    const view = control();
    const pending = deferred();
    const completion = runLineOfBusinessRequest({ ...view.options, operation, request: () => pending.promise });
    assert.deepEqual(view.events, [["busy", operation], ["error", null]]);
    await runLineOfBusinessRequest({ ...view.options, operation, request() { assert.fail("duplicate request"); } });
    const response = { status: operation === "preview" ? "CHANGES_REQUIRED" : "SAVED", line_of_business: "HOSPICE" };
    pending.resolve(response);
    await completion;
    assert.equal(view.state.response, response);
    assert.equal(view.state.busy, null);
    assert.equal(view.state.saved, operation === "preview" ? 0 : 1);
    for (const cache of caches) assert.equal(cache.peek(cachedRequest).status, operation === "preview" ? "ready" : "loading");
    view.unmount();
  }
  clearCurrentConfigurations();
});

test("late LOB saves invalidate every cache and pending read without updating an unmounted control", async () => {
  for (const operation of ["save", "apply"]) {
    const view = control();
    const pending = deferred();
    const completion = runLineOfBusinessRequest({ ...view.options, operation, request: () => pending.promise });
    view.unmount();
    const oldReads = caches.map(() => deferred());
    const reads = caches.map((cache, index) => cache.load(cachedRequest, () => oldReads[index].promise));
    const beforeCompletion = view.events.slice();
    pending.resolve({ line_of_business: "HOSPICE" });
    await completion;
    assert.deepEqual(view.events, [...beforeCompletion, ["saved"]]);
    assert.equal(view.state.response, null);
    oldReads.forEach(read => read.resolve("obsolete settings"));
    await Promise.all(reads);
    for (const cache of caches) assert.equal(cache.peek(cachedRequest).status, "loading");
  }
  clearCurrentConfigurations();
});

test("late Preview results and failures from all LOB operations cannot update a removed control", async () => {
  for (const operation of ["save", "preview", "apply"]) {
    const view = control();
    const pending = deferred();
    const completion = runLineOfBusinessRequest({ ...view.options, operation, request: () => pending.promise,
      onError() { assert.fail("old error policy must not run"); } });
    view.unmount();
    const beforeCompletion = view.events.slice();
    pending.reject(new ApiClientError("stale_preview", "private diagnostics", 409));
    await completion;
    assert.deepEqual(view.events, beforeCompletion);
    assert.equal(view.state.saved, 0);
  }
  const view = control();
  const pending = deferred();
  const completion = runLineOfBusinessRequest({ ...view.options, operation: "preview", request: () => pending.promise });
  view.unmount();
  const beforeCompletion = view.events.slice();
  pending.resolve({ status: "CHANGES_REQUIRED" });
  await completion;
  assert.deepEqual(view.events, beforeCompletion);
});

test("A to B to A creates a new request owner that an old success or failure cannot unlock", async () => {
  for (const outcome of ["success", "failure"]) {
    const originalA = control();
    const oldResponse = deferred();
    const oldCompletion = runLineOfBusinessRequest({ ...originalA.options, operation: "apply", request: () => oldResponse.promise });
    originalA.unmount();
    const b = control();
    b.unmount();
    const returnedA = control();
    const freshResponse = deferred();
    const freshCompletion = runLineOfBusinessRequest({ ...returnedA.options, operation: "preview", request: () => freshResponse.promise });
    if (outcome === "success") oldResponse.resolve({ line_of_business: "HOSPICE" });
    else oldResponse.reject(new Error("old request failed"));
    await oldCompletion;
    assert.equal(returnedA.state.busy, "preview");
    assert.equal(returnedA.state.error, null);
    await runLineOfBusinessRequest({ ...returnedA.options, operation: "preview", request() { assert.fail("old finally released new gate"); } });
    const current = { status: "CHANGES_REQUIRED", preview_state_hash: "fresh hash" };
    freshResponse.resolve(current);
    await freshCompletion;
    assert.equal(returnedA.state.response, current);
    assert.equal(returnedA.state.busy, null);
    returnedA.unmount();
  }
});

test("effect cleanup and reactivation isolate requests even when React reuses the scope", async () => {
  const scope = new LineOfBusinessRequestScope();
  const first = control(scope);
  const oldResponse = deferred();
  const oldCompletion = runLineOfBusinessRequest({ ...first.options, operation: "preview", request: () => oldResponse.promise });
  first.unmount();
  await runLineOfBusinessRequest({ ...first.options, operation: "preview", request() { assert.fail("unmounted scope started request"); } });
  const next = control(scope);
  first.unmount(); // A repeated old cleanup must not disable the new lifetime.
  const freshResponse = deferred();
  const freshCompletion = runLineOfBusinessRequest({ ...next.options, operation: "preview", request: () => freshResponse.promise });
  oldResponse.resolve("old response");
  await oldCompletion;
  assert.equal(first.state.response, null);
  assert.equal(next.state.busy, "preview");
  await runLineOfBusinessRequest({ ...next.options, operation: "preview", request() { assert.fail("old request unlocked new lifetime"); } });
  freshResponse.resolve("new response");
  await freshCompletion;
  assert.equal(next.state.response, "new response");
  next.unmount();
});

test("current failures use the editor's error policy and release ownership for retry", async () => {
  const view = control();
  const pending = deferred();
  const errors = [];
  const completion = runLineOfBusinessRequest({ ...view.options, operation: "apply", request: () => pending.promise,
    onError(error) { errors.push(error); view.options.setError(error); } });
  pending.reject(new ApiClientError("stale_preview", "private diagnostics", 409));
  await completion;
  assert.deepEqual(errors, [{ category: "stale_preview", message: "Configuration changed since the preview." }]);
  assert.equal(view.state.saved, 0);
  assert.equal(view.state.busy, null);
  await runLineOfBusinessRequest({ ...view.options, operation: "preview", request: async () => "fresh preview" });
  assert.equal(view.state.error, null);
  assert.equal(view.state.response, "fresh preview");
  view.unmount();
});

test("current-LOB reads discard old success, failure, and loading cleanup during context refresh", async t => {
  const reads = [];
  t.mock.method(apiClient, "lineOfBusinessCurrent", request => {
    const response = deferred(); reads.push({ request, ...response }); return response.promise;
  });
  const state = { current: null, error: null, loading: false };
  const callbacks = {
    setCurrent(value) { state.current = value; }, setError(value) { state.error = value; },
    setLoading(value) { state.loading = value; },
  };
  const cancelA = readCurrentLineOfBusiness("SYN-A", callbacks);
  cancelA();
  const cancelB = readCurrentLineOfBusiness("SYN-B", callbacks);
  cancelB();
  const cancelFreshA = readCurrentLineOfBusiness("SYN-A", callbacks);
  reads[0].resolve({ status: "DEFINED", line_of_business: "HOME_HEALTH" });
  reads[1].reject(new Error("old B failure"));
  await flush();
  assert.deepEqual(state, { current: null, error: null, loading: true });
  const fresh = { status: "DEFINED", line_of_business: "HOSPICE" };
  reads[2].resolve(fresh);
  await flush();
  assert.deepEqual(state, { current: fresh, error: null, loading: false });
  cancelFreshA();
});

test("a saved notification can refresh the displayed payor, including the original payor after a failed switch", async t => {
  const reads = [];
  t.mock.method(apiClient, "lineOfBusinessCurrent", request => {
    const response = deferred(); reads.push({ request, ...response }); return response.promise;
  });
  for (const displayedPayor of ["SYN-B", "SYN-A"]) {
    const view = control();
    const state = { current: null, loading: false, error: null };
    const callbacks = {
      setCurrent(value) { state.current = value; }, setLoading(value) { state.loading = value; },
      setError(value) { state.error = value; },
    };
    let cancelRead = () => {};
    const saved = deferred();
    const completion = runLineOfBusinessRequest({ ...view.options, operation: "save", request: () => saved.promise,
      onSaved() { cancelRead(); cancelRead = readCurrentLineOfBusiness(displayedPayor, callbacks); } });
    view.unmount();
    saved.resolve({ line_of_business: "HOSPICE" });
    await completion;
    assert.deepEqual(reads.at(-1).request, { payor_guid: displayedPayor });
    assert.equal(state.current, null, "the original save response is not injected into the displayed context");
    const fresh = { status: "DEFINED", line_of_business: displayedPayor === "SYN-A" ? "HOSPICE" : "HOME_HEALTH" };
    reads.at(-1).resolve(fresh);
    await flush();
    assert.equal(state.current, fresh);
    assert.equal(state.loading, false);
    cancelRead();
  }
});
