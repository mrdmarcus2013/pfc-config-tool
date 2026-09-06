import test from "node:test";
import assert from "node:assert/strict";
import { technicalContextRows } from "../.test-build/app/technical-context.js";

const launch = {
  payor_guid: "launch-payor",
  plan_guid: "launch-plan",
  pfc_guid: "untrusted-launch-pfc",
  audit_user: "synthetic-audit",
};

test("Tier 2 rows show the Oracle-resolved PFC and both template GUIDs", () => {
  const rows = technicalContextRows(launch, {
    status: "RESOLVED",
    payor_guid: "resolved-payor",
    plan_guid: "resolved-plan",
    pfc_guid: "resolved-pfc",
    billing_form_code: "837I_5010",
    form_template_guid: "form-template",
    user_form_template_guid: "user-template",
    form_template_name: "Home Health",
    user_form_template_name: "Provider Taxonomy On",
  }, false);

  assert.deepEqual(rows, [
    { label: "Payor GUID", value: "resolved-payor" },
    { label: "Plan GUID", value: "resolved-plan" },
    { label: "PFC GUID", value: "resolved-pfc" },
    { label: "Form Template GUID", value: "form-template" },
    { label: "Form Template Name", value: "Home Health" },
    { label: "User Form Template GUID", value: "user-template" },
    { label: "User Form Template Name", value: "Provider Taxonomy On" },
  ]);
});

test("Tier 2 rows label absent templates and never trust the launch PFC", () => {
  const resolved = technicalContextRows(launch, {
    status: "RESOLVED",
    payor_guid: "resolved-payor",
    plan_guid: null,
    pfc_guid: "resolved-pfc",
    billing_form_code: "837I_5010",
    form_template_guid: null,
    user_form_template_guid: null,
  }, false);
  assert.deepEqual(resolved.map((row) => row.value), [
    "resolved-payor", "None", "resolved-pfc", "None", "None", "None", "None",
  ]);

  const unavailable = technicalContextRows(launch, null, false);
  assert.equal(unavailable.find((row) => row.label === "PFC GUID").value, "Unavailable");
  assert.notEqual(unavailable.find((row) => row.label === "PFC GUID").value, launch.pfc_guid);
});

test("assigned GUIDs with unavailable names do not appear unassigned", () => {
  const rows = technicalContextRows(launch, {
    form_template_guid: "unknown-form", user_form_template_guid: "unknown-user",
  }, false);
  assert.equal(rows.find((row) => row.label === "Form Template Name").value, "Unavailable");
  assert.equal(rows.find((row) => row.label === "User Form Template Name").value, "Unavailable");
});
