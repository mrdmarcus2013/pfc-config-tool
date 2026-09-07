import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ClaimFieldPanelHeader } from "../.test-build/app/claim-field-panel-header.js";
import { FieldEditor } from "../.test-build/app/field-editor.js";
import { ValueCodesEditor } from "../.test-build/app/value-codes-editor.js";
import { RemarksEditor } from "../.test-build/app/remarks-editor.js";
import { CLAIM_FIELD_CATALOG } from "../.test-build/data/claim-field-catalog.js";

const corruptedClose = String.fromCodePoint(0x00c3, 0x2014);
const unicodeMultiply = String.fromCodePoint(0x00d7);

test("shared claim-field panel header uses an accessible ASCII close control", () => {
  const markup = renderToStaticMarkup(
    React.createElement(ClaimFieldPanelHeader, { title: "Value Codes", onClose: () => {} }),
  );
  assert.match(markup, /class="icon-button"/);
  assert.match(markup, /aria-label="Close"/);
  assert.match(markup, />X<\/button>/);
  assert.ok(!markup.includes(corruptedClose));
  assert.ok(!markup.includes(unicodeMultiply));
});

test("claim-field editors render labelled focusable panels and wait for current state", () => {
  const context = { payor_guid: "synthetic-payor", plan_guid: null, pfc_guid: "synthetic-pfc", audit_user: "synthetic-audit" };
  for (const [fieldNumber, component, title] of [
    ["39-41", ValueCodesEditor, "Value Codes"],
    ["80", RemarksEditor, "Remarks"],
    ["77", FieldEditor, "Field 77 — Operating Provider"],
    ["81", FieldEditor, "Field 81cc"],
  ]) {
    const field = CLAIM_FIELD_CATALOG.find(candidate => candidate.fieldNumber === fieldNumber);
    const markup = renderToStaticMarkup(React.createElement(component, {
      field, context, lineOfBusiness: "HOME_HEALTH", supportDeveloperMode: false, onClose() {},
    }));
    assert.match(markup, /role="dialog" aria-modal="true" aria-labelledby="editor-title"/);
    assert.match(markup, /<aside[^>]+tabindex="-1"/);
    assert.ok(markup.includes(`<h2 id="editor-title">${title}</h2>`));
    assert.match(markup, /aria-label="Close">X<\/button>/);
    assert.match(markup, /Loading current configuration/);
    assert.match(markup, /class="primary-button" disabled="">Apply Changes/);
    assert.doesNotMatch(markup, /synthetic-audit|Technical details/);
    assert.ok(!markup.includes(corruptedClose));
    assert.ok(!markup.includes(unicodeMultiply));
  }
});
