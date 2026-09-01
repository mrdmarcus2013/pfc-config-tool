import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { EditorFooter } from "../.test-build/app/editor-footer.js";
import {
  PREVIEW_REQUIRED_MESSAGE,
  currentPreview,
  editorActionState,
  previewAfterError,
} from "../.test-build/app/workflow.js";

const forbiddenPreviewLabel = ["Preview", "Again"].join(" ");
const frontendRoot = dirname(dirname(fileURLToPath(import.meta.url)));

const filesUnder = (directory) => readdirSync(directory, { withFileTypes: true })
  .flatMap((entry) => entry.isDirectory()
    ? filesUnder(join(directory, entry.name))
    : [join(directory, entry.name)]);

const preview = {
  status: "PREVIEW",
  option_code: "PROVIDER_TAXONOMY_ON",
  display_label: "Provider Taxonomy ON",
  field_number: "81",
  state_hash: "SYNTHETIC_HASH",
  change_count: 1,
  summary: "Synthetic preview",
  pfc_guid: "synthetic-pfc",
  debug_changes: [],
};

const state = (overrides = {}) => editorActionState({
  dirty: true,
  preview: null,
  busy: null,
  applyCompleted: false,
  ...overrides,
});

const footerProps = (actionState, overrides = {}) => ({
  actionState,
  previewDisabled: false,
  previewLabel: "Preview",
  onDismiss: () => {},
  onPreview: () => {},
  onApply: () => {},
  ...overrides,
});

test("a proposed change without Preview explains why Apply is disabled", () => {
  const actionState = state();
  assert.equal(actionState.previewRequired, true);
  assert.equal(actionState.previewVisible, true);
  assert.equal(actionState.applyEnabled, false);
  assert.equal(actionState.dismissLabel, "Cancel");
  assert.equal(actionState.configurationCompleted, false);

  const markup = renderToStaticMarkup(
    React.createElement(EditorFooter, footerProps(actionState)),
  );
  assert.match(markup, new RegExp(PREVIEW_REQUIRED_MESSAGE.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.match(markup, />Preview<\/button>/);
  assert.match(markup, /class="primary-button" disabled="">Apply Changes/);
});

test("guidance is grouped with Preview and Apply while Cancel stays isolated", () => {
  const element = EditorFooter(footerProps(state()));
  const dismissButton = element.props.children[0];
  const actionRegion = element.props.children[1];
  const guidance = actionRegion.props.children[0];
  const actionButtons = actionRegion.props.children[1];

  assert.equal(dismissButton.props.children, "Cancel");
  assert.equal(actionRegion.props.className, "editor-action-region");
  assert.equal(guidance.props.children, PREVIEW_REQUIRED_MESSAGE);
  assert.equal(actionButtons.props.className, "editor-action-buttons");
});

test("a successful Preview hides Preview and guidance while enabling Apply", () => {
  const actionState = state({ preview });
  assert.equal(actionState.previewRequired, false);
  assert.equal(actionState.previewVisible, false);
  assert.equal(actionState.applyEnabled, true);

  const markup = renderToStaticMarkup(
    React.createElement(EditorFooter, footerProps(actionState)),
  );
  assert.doesNotMatch(markup, /Preview is required/);
  assert.doesNotMatch(markup, />Preview<\/button>/);
  assert.doesNotMatch(markup, new RegExp(forbiddenPreviewLabel));
  assert.match(markup, /class="primary-button">Apply Changes/);
});

test("changing a selection invalidates Preview and restores the normal Preview action", () => {
  const record = { identity: "payor||audit|PROVIDER_TAXONOMY_ON", response: preview };
  assert.equal(currentPreview(record, record.identity), preview);
  const invalidated = currentPreview(record, "payor||audit|PROVIDER_TAXONOMY_OFF");
  assert.equal(invalidated, null);

  const actionState = state({ preview: invalidated });
  assert.equal(actionState.applyEnabled, false);
  assert.equal(actionState.previewVisible, true);
  assert.equal(actionState.previewRequired, true);
  const markup = renderToStaticMarkup(React.createElement(EditorFooter, footerProps(actionState)));
  assert.match(markup, />Preview<\/button>/);
  assert.doesNotMatch(markup, new RegExp(forbiddenPreviewLabel));
  assert.match(markup, /Preview is required before changes can be applied/);
});

test("a stale failure clears the hash and returns the normal Preview action", () => {
  const retained = { identity: "proposal", response: preview };
  const cleared = previewAfterError(retained, "stale_preview");
  assert.equal(cleared, null);

  const actionState = state({ preview: cleared });
  const markup = renderToStaticMarkup(React.createElement(EditorFooter, footerProps(actionState)));
  assert.equal(actionState.previewVisible, true);
  assert.equal(actionState.previewRequired, true);
  assert.equal(actionState.applyEnabled, false);
  assert.match(markup, />Preview<\/button>/);
  assert.doesNotMatch(markup, new RegExp(forbiddenPreviewLabel));
});

test("unchanged and NO_CHANGE configurations do not request another Preview", () => {
  const unchanged = state({ dirty: false });
  const noChange = state({
    dirty: false,
    preview: { ...preview, status: "NO_CHANGE", change_count: 0 },
  });
  assert.equal(unchanged.previewRequired, false);
  assert.equal(unchanged.previewVisible, true);
  assert.equal(unchanged.applyEnabled, false);
  assert.equal(noChange.previewRequired, false);
  assert.equal(noChange.applyEnabled, false);
});

test("confirmed Apply changes Cancel to Close and dismisses without an API action", () => {
  const actionState = state({ dirty: false, applyCompleted: true });
  assert.equal(actionState.dismissLabel, "Close");
  assert.equal(actionState.configurationCompleted, true);
  assert.equal(actionState.previewRequired, false);
  assert.equal(actionState.applyEnabled, false);

  let dismissCalls = 0;
  let apiCalls = 0;
  const element = EditorFooter(footerProps(actionState, {
    previewDisabled: true,
    onDismiss: () => { dismissCalls += 1; },
    onPreview: () => { apiCalls += 1; },
    onApply: () => { apiCalls += 1; },
  }));
  const dismissButton = element.props.children[0];
  dismissButton.props.onClick();
  assert.equal(dismissCalls, 1);
  assert.equal(apiCalls, 0);

  const markup = renderToStaticMarkup(element);
  assert.match(markup, />Close<\/button>/);
  assert.doesNotMatch(markup, />Cancel<\/button>/);
  assert.doesNotMatch(markup, />Preview<\/button>/);
  assert.doesNotMatch(markup, /Apply Changes/);
  assert.doesNotMatch(markup, /Preview is required/);
  assert.doesNotMatch(markup, new RegExp(forbiddenPreviewLabel));
});

test("a new edit after successful Apply returns to Cancel and Preview-required state", () => {
  const actionState = state({ dirty: true, applyCompleted: true });
  assert.equal(actionState.dismissLabel, "Cancel");
  assert.equal(actionState.configurationCompleted, false);
  assert.equal(actionState.previewRequired, true);
  assert.equal(actionState.applyEnabled, false);
  const markup = renderToStaticMarkup(React.createElement(EditorFooter, footerProps(actionState)));
  assert.match(markup, />Cancel<\/button>/);
  assert.match(markup, />Preview<\/button>/);
  assert.match(markup, /class="primary-button" disabled="">Apply Changes/);
});

test("the obsolete combined preview label is absent from frontend source and tests", () => {
  const files = [
    ...filesUnder(join(frontendRoot, "src")),
    ...filesUnder(join(frontendRoot, "tests")),
    join(frontendRoot, "README.md"),
  ];
  for (const file of files) {
    assert.doesNotMatch(readFileSync(file, "utf8"), new RegExp(forbiddenPreviewLabel), file);
  }
});
