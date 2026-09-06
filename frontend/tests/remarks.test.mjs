import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  REMARKS_CUSTOM_REMARK_MAX_LENGTH,
  normalizedCustomRemark,
  remarksIdentity,
  remarksIntentFromCurrent,
  remarksIntentIsValid,
  remarksIntentMatchesCurrent,
  remarksRequest,
} from "../.test-build/app/remarks.js";
import { CLAIM_FIELD_CATALOG } from "../.test-build/data/claim-field-catalog.js";
import {
  catalogFieldIsAvailable,
  catalogFieldIsEditable,
  fieldEditorRoute,
  selectCatalogFieldForEditor,
} from "../.test-build/app/workflow.js";
import { fieldsUnlocked } from "../.test-build/app/line-of-business.js";

const context = { payor_guid: "payor", plan_guid: null, pfc_guid: "pfc", audit_user: "audit" };
const root = dirname(dirname(fileURLToPath(import.meta.url)));

test("Field 80 Remarks is LOB-gated and available for both supported LOBs", () => {
  const field = CLAIM_FIELD_CATALOG.find((candidate) => candidate.fieldNumber === "80");
  assert.equal(field?.label, "Remarks");
  assert.equal(field?.capabilityKey, "remarks");
  assert.equal(catalogFieldIsAvailable(field,
    [{ field_number: "80", field_label: "Remarks", options: [] }]), true);
  assert.equal(catalogFieldIsAvailable(field, []), true,
    "the registered structured endpoint does not require public option codes");
  assert.equal(fieldsUnlocked(null), false);
  assert.equal(fieldsUnlocked("HOME_HEALTH"), true);
  assert.equal(fieldsUnlocked("HOSPICE"), true);
  assert.equal(catalogFieldIsEditable(field, [], "HOME_HEALTH"), true);
  assert.equal(catalogFieldIsEditable(field, [], "HOSPICE"), true);
  assert.equal(catalogFieldIsEditable(field, [], null), false);
});

test("click selection for editable Field 80 routes to the existing Remarks editor", () => {
  const remarks = CLAIM_FIELD_CATALOG.find((field) => field.fieldNumber === "80");
  const selected = selectCatalogFieldForEditor(remarks, [], "HOME_HEALTH");
  assert.equal(selected, remarks);
  assert.equal(fieldEditorRoute(selected), "remarks");

  const appSource = readFileSync(join(root, "src", "App.tsx"), "utf8");
  assert.match(appSource, /onClick=\{\(\) => setSelectedField\(/);
  assert.match(appSource, /selectCatalogFieldForEditor\(field, optionFields, lob\)/);
  assert.match(appSource, /fieldEditorRoute\(selectedField\) === "remarks"/);
  assert.match(appSource, /<RemarksEditor field=\{selectedField\}/);
});

test("undefined LOB and unsupported neutral fields cannot be selected", () => {
  const remarks = CLAIM_FIELD_CATALOG.find((field) => field.fieldNumber === "80");
  const unsupported = CLAIM_FIELD_CATALOG.find((field) => field.fieldNumber === "78");
  assert.equal(selectCatalogFieldForEditor(remarks, [], null), null);
  assert.equal(catalogFieldIsAvailable(unsupported, []), false);
  assert.equal(catalogFieldIsEditable(unsupported, [], "HOME_HEALTH"), false);
  assert.equal(selectCatalogFieldForEditor(unsupported, [], "HOSPICE"), null);
});

test("Default and Custom current states initialize without losing exact text", () => {
  const base = { configuration_status: "RESOLVED", line_of_business: "HOME_HEALTH",
    canonical_status: "INHERITED", display_summary: "Default", pfc_guid: "pfc", debug: {} };
  const defaultIntent = remarksIntentFromCurrent({ ...base, mode: "DEFAULT", custom_remark: null });
  assert.deepEqual(defaultIntent, { mode: "DEFAULT", customRemark: "" });
  const text = "Call provider before processing";
  const customIntent = remarksIntentFromCurrent({ ...base, mode: "CUSTOM", custom_remark: text });
  assert.deepEqual(customIntent, { mode: "CUSTOM", customRemark: text });
  assert.equal(remarksIntentMatchesCurrent({ ...base, mode: "CUSTOM", custom_remark: text }, customIntent), true);
});

test("custom text validation enforces required and temporary configured maximum", () => {
  assert.equal(REMARKS_CUSTOM_REMARK_MAX_LENGTH, 100);
  assert.equal(remarksIntentIsValid({ mode: "CUSTOM", customRemark: "" }), false);
  assert.equal(remarksIntentIsValid({ mode: "CUSTOM", customRemark: "   " }), false);
  assert.equal(remarksIntentIsValid({ mode: "CUSTOM", customRemark: "X".repeat(100) }), true);
  assert.equal(remarksIntentIsValid({ mode: "CUSTOM", customRemark: "X".repeat(101) }), false);
  assert.equal(remarksIntentIsValid({ mode: "DEFAULT", customRemark: "preserved draft" }), true);
  assert.equal(normalizedCustomRemark("  Exact internal  spacing  "), "Exact internal  spacing");
});

test("requests send trimmed dynamic text for Custom and no text for Default", () => {
  assert.deepEqual(remarksRequest(context, { mode: "CUSTOM", customRemark: "  My  remark  " }), {
    payor_guid: "payor", plan_guid: null, mode: "CUSTOM",
    custom_remark: "My  remark", audit_user: "audit",
  });
  assert.equal(remarksRequest(context,
    { mode: "DEFAULT", customRemark: "unsaved draft" }).custom_remark, null);
});

test("mode, exact sent text, and LOB invalidate a previous Preview identity", () => {
  const first = remarksIdentity(context, "HOME_HEALTH", { mode: "CUSTOM", customRemark: "First" });
  assert.notEqual(first, remarksIdentity(context, "HOME_HEALTH", { mode: "CUSTOM", customRemark: "Second" }));
  assert.notEqual(first, remarksIdentity(context, "HOME_HEALTH", { mode: "DEFAULT", customRemark: "First" }));
  assert.notEqual(first, remarksIdentity(context, "HOSPICE", { mode: "CUSTOM", customRemark: "First" }));
});

test("shared editor includes radios, textarea, counter, validation, hash apply, refresh, and gated diagnostics", () => {
  const source = readFileSync(join(root, "src", "app", "remarks-editor.tsx"), "utf8");
  assert.match(source, /Use standard remarks/);
  assert.match(source, /Use a custom remark/);
  assert.match(source, /<textarea aria-label="Custom remark"/);
  assert.match(source, /maxLength=\{REMARKS_CUSTOM_REMARK_MAX_LENGTH\}/);
  assert.match(source, /intent\.customRemark\.length/);
  assert.match(source, /!dirty \|\| !valid/);
  assert.match(source, /setPreviewRecord\(null\)/);
  assert.match(source, /expected_state_hash: preview!\.state_hash/);
  assert.match(source, /await loadCurrent\(true\)/);
  assert.match(source, /supportDeveloperMode &&/);
});

test("LOB changes close the editor and clear shared current-state cache", () => {
  const source = readFileSync(join(root, "src", "App.tsx"), "utf8");
  assert.match(source, /onChangeStarted=\{\(\) => \{ setSelectedField\(null\)/);
  assert.match(source, /clearCurrentConfigurations\(\)/);
});
