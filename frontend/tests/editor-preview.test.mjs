import test from "node:test";
import assert from "node:assert/strict";
import { ApiClientError } from "../.test-build/api/client.js";
import { runEditorPreview } from "../.test-build/app/editor-preview.js";
import { SingleFlightGate, currentPreview, editorActionState } from "../.test-build/app/workflow.js";

const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const ready = { status: "PREVIEW", change_count: 1, debug_changes: [], state_hash: "SYNTHETIC_HASH" };

function previewState() {
  const state = { busy: null, error: null, success: true, record: null };
  const events = [];
  const callbacks = {
    setBusy(value) { state.busy = value; events.push(["busy", value]); },
    setError(value) { state.error = value; events.push(["error", value]); },
    setSuccess(value) { state.success = value; events.push(["success", value]); },
    setPreviewRecord(value) { state.record = value; events.push(["preview", value]); },
  };
  return { state, events, options: { ...callbacks, canPreview: true, gate: new SingleFlightGate(), identity: "original-proposal" } };
}

test("Preview immediately enters busy state and preserves the exact response and proposal identity", async () => {
  const { state, events, options } = previewState();
  const response = deferred();
  const completion = runEditorPreview({ ...options, request: () => response.promise });
  assert.deepEqual(events, [["busy", "preview"], ["error", null], ["success", false]]);
  assert.equal(state.record, null);
  assert.equal(options.gate.tryEnter(), false);
  response.resolve(ready);
  await completion;
  assert.deepEqual(state.record, { identity: "original-proposal", response: ready });
  assert.equal(state.record.response, ready);
  assert.deepEqual(events.slice(3), [["preview", state.record], ["busy", null]]);
  assert.equal(state.success, false, "Preview is not Apply success");
  assert.equal(options.gate.tryEnter(), true);
  options.gate.exit();
});

test("a rapid second Preview makes no request, changes no state, and does not release the first request's gate", async () => {
  const { events, options } = previewState();
  const response = deferred();
  let requests = 0;
  const request = () => { requests++; return response.promise; };
  const first = runEditorPreview({ ...options, request });
  await runEditorPreview({ ...options, request });
  assert.equal(requests, 1);
  assert.equal(events.length, 3);
  assert.equal(options.gate.tryEnter(), false);
  response.resolve(ready);
  await first;
  assert.equal(options.gate.tryEnter(), true);
  options.gate.exit();
});

test("an invalid or unchanged proposal never acquires the gate or invokes request callbacks", async () => {
  const { events, options } = previewState();
  await runEditorPreview({ ...options, canPreview: false, request() { assert.fail("request must not run"); } });
  assert.deepEqual(events, []);
  assert.equal(options.gate.tryEnter(), true);
  await runEditorPreview({ ...options, request() { assert.fail("another operation owns this gate"); } });
  assert.deepEqual(events, []);
  assert.equal(options.gate.tryEnter(), false);
  options.gate.exit();
});

test("Preview failure clears a prior review, reports a safe error, and releases the gate for retry", async () => {
  const { state, options } = previewState();
  state.record = { identity: "older-proposal", response: ready };
  const response = deferred();
  const first = runEditorPreview({ ...options, request: () => response.promise });
  assert.equal(state.record.identity, "older-proposal", "the existing review is retained while loading");
  response.reject(new ApiClientError("stale_preview", "ORA-raw diagnostics", 409));
  await first;
  assert.equal(state.record, null);
  assert.equal(state.busy, null);
  assert.deepEqual(state.error, { category: "stale_preview", message: "Configuration changed since the preview." });
  const retry = deferred();
  const second = runEditorPreview({ ...options, request: () => retry.promise });
  assert.equal(state.error, null);
  assert.equal(state.busy, "preview");
  retry.resolve(ready);
  await second;
  assert.equal(state.record.response, ready);
  assert.equal(state.busy, null);
});

test("synchronous request failures use the same safe cleanup and permit a later Preview", async () => {
  const { state, options } = previewState();
  await runEditorPreview({ ...options, request() { throw new Error("internal diagnostics"); } });
  assert.equal(state.record, null);
  assert.equal(state.busy, null);
  assert.deepEqual(state.error, { category: "server_failure", message: "The request could not be completed safely." });
  await runEditorPreview({ ...options, request: async () => ready });
  assert.equal(state.error, null);
  assert.equal(state.record.response, ready);
});

test("editing during Preview leaves the late response ineligible for the new proposal", async () => {
  const { state, options } = previewState();
  const response = deferred();
  const completion = runEditorPreview({ ...options, request: () => response.promise });
  const newIdentity = "changed-proposal";
  response.resolve(ready);
  await completion;
  assert.equal(currentPreview(state.record, newIdentity), null);
  assert.deepEqual(editorActionState({ dirty: true, preview: currentPreview(state.record, newIdentity), busy: state.busy, applyCompleted: state.success }), {
    applyEnabled: false, dismissLabel: "Cancel", configurationCompleted: false,
    previewVisible: true, previewRequired: true,
  });
});

test("NO_CHANGE and blocked responses remain visible but never enable Apply", async () => {
  const { state, options } = previewState();
  for (const response of [
    { ...ready, status: "NO_CHANGE", change_count: 0 },
    { ...ready, debug_changes: [{ operation_code: "BLOCKED" }] },
  ]) {
    await runEditorPreview({ ...options, request: async () => response });
    assert.equal(state.record.response, response);
    const action = editorActionState({ dirty: true, preview: currentPreview(state.record, options.identity), busy: state.busy, applyCompleted: state.success });
    assert.equal(action.applyEnabled, false);
    assert.equal(action.previewRequired, false);
  }
});
