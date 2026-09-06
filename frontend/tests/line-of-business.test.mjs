import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { LineOfBusinessControl } from "../.test-build/app/line-of-business-control.js";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  fieldsUnlocked,
  lineOfBusinessLabel,
  lobApplyRequest,
  lobPreviewAfterError,
  otherLineOfBusiness,
} from "../.test-build/app/line-of-business.js";

test("undefined LOB locks fields and saved LOB unlocks them without an unset state", () => {
  assert.equal(fieldsUnlocked(null), false);
  assert.equal(fieldsUnlocked("HOME_HEALTH"), true);
  assert.equal(fieldsUnlocked("HOSPICE"), true);
  assert.equal(otherLineOfBusiness("HOME_HEALTH"), "HOSPICE");
  assert.equal(otherLineOfBusiness("HOSPICE"), "HOME_HEALTH");
  assert.equal(lineOfBusinessLabel("HOME_HEALTH"), "Home Health");
});

test("LOB apply uses the exact preview hash and no plan or PFC key", () => {
  const context = { payor_guid: "payor", plan_guid: "plan", pfc_guid: "pfc", audit_user: "audit" };
  const preview = {
    status: "CHANGES_REQUIRED", changes_required: true,
    current_line_of_business: "HOME_HEALTH", requested_line_of_business: "HOSPICE",
    managed_target_count: 4, affected_managed_target_count: 2,
    managed_her_count: 3, managed_hef_count: 9,
    preview_state_hash: "D".repeat(64), summary: "Synthetic", debug_targets: [],
  };
  assert.deepEqual(lobApplyRequest(context, preview), {
    payor_guid: "payor", requested_line_of_business: "HOSPICE",
    expected_state_hash: "D".repeat(64), audit_user: "audit",
  });
});

test("stale LOB preview is discarded and must be previewed again", () => {
  const preview = { preview_state_hash: "HASH" };
  assert.equal(lobPreviewAfterError(preview, "stale_preview"), null);
  assert.equal(lobPreviewAfterError(preview, "server_failure"), preview);
});

test("page contains initial-save locking and two-stage all-plan reset wording", () => {
  const root = dirname(dirname(fileURLToPath(import.meta.url)));
  const appSource = readFileSync(join(root, "src", "App.tsx"), "utf8");
  const source = readFileSync(join(root, "src", "app", "line-of-business-control.tsx"), "utf8");
  assert.match(source, /Save Line of Business/);
  assert.match(appSource, /Select and save a Line of Business before configuring claim fields/);
  assert.match(source, /Change Line of Business\?/);
  assert.match(source, /This applies to all plans under this payor/);
  assert.match(source, /Confirm Reset/);
  assert.match(source, /Reset Fields and Change to/);
  assert.match(source, /clearCurrentConfigurations\(\)/);
  assert.doesNotMatch(source.replace(/SUPPORT_DEVELOPER_MODE[\s\S]*?details>/g, ""), />HER<|>HEF</);
});

test("LOB control preserves initial-save and saved-payor rendering", () => {
  const props = {
    context: { payor_guid: "synthetic-payor", plan_guid: null, pfc_guid: "synthetic-pfc", audit_user: "synthetic-audit" },
    current: { status: "UNDEFINED", line_of_business: null },
    loading: false, disabled: false, onChanged() {}, onChangeStarted() {},
  };
  const initial = renderToStaticMarkup(React.createElement(LineOfBusinessControl, props));
  assert.match(initial, /disabled="">Save Line of Business/);
  assert.doesNotMatch(initial, /Change Line of Business/);
  for (const [lineOfBusiness, label] of [["HOME_HEALTH", "Home Health"], ["HOSPICE", "Hospice"]]) {
    const saved = renderToStaticMarkup(React.createElement(LineOfBusinessControl, {
      ...props, current: { status: "DEFINED", line_of_business: lineOfBusiness }, disabled: true,
    }));
    assert.ok(saved.includes(`Saved for this payor. Every plan uses ${label}.`));
    assert.match(saved, /disabled="">Change Line of Business/);
    assert.doesNotMatch(saved, /Save Line of Business|synthetic-audit/);
  }
});
