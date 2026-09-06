import test from "node:test";
import assert from "node:assert/strict";
import { ApiClientError, apiClient } from "../.test-build/api/client.js";
import { safeError } from "../.test-build/app/workflow.js";

test("Copy displays the specific billing-form and Line of Business blockers", () => {
  for (const message of [
    "The billing form must match the source for every destination context.",
    "Source and destination Line of Business must match.",
    "Choose a destination payor different from the source.",
  ]) {
    assert.deepEqual(safeError(new ApiClientError("copy_blocked", message, 409)),
      { category: "copy_blocked", message });
  }
});

test("Copy source validation provides an actionable reason instead of an empty catalog", async () => {
  const message = "Save Line of Business for the source payor before copying.";
  const previous = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({ error: {
    category: "copy_source_blocked", message,
  } }), { status: 409 });
  try {
    await assert.rejects(
      apiClient.eligibleCopyDestinations({ source_payor_guid: "SYN-SOURCE", source_plan_guid: null, audit_user: "SYN-USER" }),
      (error) => {
        assert.deepEqual(safeError(error), { category: "copy_source_blocked", message });
        return true;
      },
    );
  } finally {
    globalThis.fetch = previous;
  }
});

test("Copy errors never expose unknown backend text or accept a message from another category", () => {
  for (const [category, message] of [
    ["copy_blocked", "ORA-20104 at PRIVATE_SCHEMA.INTERNAL_PROC: sensitive database detail"],
    ["copy_source_blocked", "ORA-20010: private source identifiers"],
    ["copy_source_blocked", "Source and destination Line of Business must match."],
    ["application_failure", "Save Line of Business for the source payor before copying."],
  ]) {
    const safe = safeError(new ApiClientError(category, message, 409));
    assert.notEqual(safe.message, message);
    assert.doesNotMatch(safe.message, /ORA-|PRIVATE_SCHEMA|sensitive|private source/);
  }
  assert.equal(safeError(new ApiClientError("copy_source_blocked", "unknown", 409)).message,
    "The source configuration must be corrected before copying. Review the selected payor and plan.");
});

test("stale-preview handling retains its existing category and refresh instruction", () => {
  assert.deepEqual(safeError(new ApiClientError("stale_preview", "private backend text", 409)), {
    category: "stale_preview", message: "Configuration changed since the preview.",
  });
});
