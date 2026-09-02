import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { ClaimFieldPanelHeader } from "../.test-build/app/claim-field-panel-header.js";

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

test("Value Codes, Service Facility, and Provider Taxonomy share the panel header", () => {
  const root = dirname(dirname(fileURLToPath(import.meta.url)));
  const source = readFileSync(join(root, "src", "App.tsx"), "utf8");
  assert.equal((source.match(/<ClaimFieldPanelHeader/g) ?? []).length, 2);
  assert.match(source, /ClaimFieldPanelHeader title="Value Codes"/);
  assert.match(source, /ClaimFieldPanelHeader title=\{fieldEditorTitle\(field\)\}/);
  assert.match(source, /"service-facility"/);
  assert.match(source, /"provider-taxonomy"/);
  assert.ok(!source.includes(corruptedClose));
  assert.ok(!source.includes(unicodeMultiply));
});
