import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ApiClientError, apiClient } from "../.test-build/api/client.js";
import { safeError } from "../.test-build/app/workflow.js";
import { CopyErrorMessage, copyErrorPresentation } from "../.test-build/app/payor-copy-panel.js";
import { safeCopyTechnicalErrorMessage } from "../.test-build/app/copy-errors.js";

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

test("eligible-destination and Preview/Apply errors put vetted template diagnoses only in Tier 2 details", async () => {
  const source = { source_payor_guid:"SYN-A",source_plan_guid:null,audit_user:"SYN-AUDIT" };
  const request = { ...source, destination_payor_guid:"SYN-B" };
  const cases = [
    [() => apiClient.eligibleCopyDestinations(source), "copy_source_blocked",
      "The source inherits invalid claim settings. Correct its template or billing-form settings before copying.",
      "The selected payor's claim settings need support review before copying."],
    [() => apiClient.previewPayorCopy(request), "copy_blocked",
      "The destination cannot resolve the same complete configuration as the source. Review payor type and template compatibility.",
      "The destination configuration is not compatible with these settings. Contact support before copying."],
    [() => apiClient.applyPayorCopy({ ...request, expected_state_hash:"A".repeat(64) }), "copy_blocked",
      "The destination cannot resolve the same complete configuration as the source. Review payor type and template compatibility.",
      "The destination configuration is not compatible with these settings. Contact support before copying."],
  ];
  const previous = globalThis.fetch;
  try {
    for (const [call, category, message, plain] of cases) {
      globalThis.fetch = async () => new Response(JSON.stringify({ error:{category,message} }), {status:409});
      await assert.rejects(call(), error => {
        const presentation = copyErrorPresentation(error);
        assert.equal(presentation.message, plain);
        assert.equal(presentation.technicalMessage, message);
        assert.equal(safeError(error).message, plain);
        const normal = renderToStaticMarkup(React.createElement(CopyErrorMessage,{error:presentation}));
        const technical = renderToStaticMarkup(React.createElement(CopyErrorMessage,{error:presentation,supportDeveloperMode:true}));
        assert.doesNotMatch(normal,/template|inherit|<details/i);
        assert.match(technical,/<details class="technical-details"><summary>Technical details<\/summary>/);
        assert.ok(technical.includes(message));
        assert.equal(technical.replace(/<details class="technical-details">[\s\S]*?<\/details>/g,""),normal);
        assert.doesNotMatch(technical,/<details[^>]*\bopen(?:=|\s|>)/);
        return true;
      });
    }
  } finally { globalThis.fetch = previous; }
});

test("Tier 2 error details never accept arbitrary diagnostics or cross-category allowlist messages", () => {
  const vetted = "The source inherits invalid claim settings. Correct its template or billing-form settings before copying.";
  for (const error of [
    new ApiClientError("copy_source_blocked", vetted + " ORA-20012 private details", 409),
    new ApiClientError("copy_blocked", vetted, 409),
    new ApiClientError("application_failure", vetted, 500),
    new Error(vetted),
  ]) {
    const presentation = copyErrorPresentation(error);
    assert.equal(presentation.technicalMessage,null);
    const html = renderToStaticMarkup(React.createElement(CopyErrorMessage,{error:presentation,supportDeveloperMode:true}));
    assert.doesNotMatch(html,/template|inherit|ORA-|private details|<details/i);
  }
  assert.equal(safeCopyTechnicalErrorMessage("copy_blocked","Source and destination Line of Business must match."),null);
});

test("audit-identity and entry-date diagnoses stay inside vetted Technical Details", () => {
  for (const [category, message] of [
    ["copy_blocked", "A valid copy request and audit identity are required."],
    ["copy_source_blocked", "A valid source payor, optional plan, and audit identity are required."],
    ["copy_source_blocked", "The source configuration is ambiguous or has a missing entry date. Review the source before copying."],
  ]) {
    const presentation = copyErrorPresentation(new ApiClientError(category,message,409));
    assert.notEqual(presentation.message,message);
    assert.doesNotMatch(presentation.message,/audit|entry date/i);
    assert.equal(presentation.technicalMessage,message);
    const normal = renderToStaticMarkup(React.createElement(CopyErrorMessage,{error:presentation}));
    const technical = renderToStaticMarkup(React.createElement(CopyErrorMessage,{error:presentation,supportDeveloperMode:true}));
    assert.equal(technical.replace(/<details class="technical-details">[\s\S]*?<\/details>/g,""),normal);
    assert.ok(technical.includes(message));
  }
});
