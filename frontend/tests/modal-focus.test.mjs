import test from "node:test";
import assert from "node:assert/strict";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { modalTabStops, mountModalFocus, refocusModal } from "../.test-build/app/modal-focus.js";
import { ModalSurface } from "../.test-build/app/modal-surface.js";

// A deliberately small DOM contract for helper tests. Browser rendering, native
// radio navigation, and React's mounted effect ordering still need browser QA.
class Element {
  constructor(document, tag, options = {}) {
    this.ownerDocument = document;
    this.tagName = tag.toUpperCase();
    this.children = [];
    this.parentElement = null;
    this.attributes = new Set(options.attributes ?? []);
    this.disabled = false;
    this.tabIndex = ["BUTTON", "INPUT", "SELECT", "TEXTAREA", "SUMMARY", "A"].includes(this.tagName) ? 0 : -1;
    this.visibility = "visible";
    this.display = "block";
    this.type = "text";
    this.name = "";
    this.form = null;
    Object.assign(this, options);
    this.attributes = new Set(options.attributes ?? []);
  }
  get isConnected() { return this === this.ownerDocument.body || Boolean(this.parentElement?.isConnected); }
  append(...elements) { for (const element of elements) { element.parentElement = this; this.children.push(element); } return elements[0]; }
  remove() { this.parentElement.children.splice(this.parentElement.children.indexOf(this), 1); this.parentElement = null; }
  contains(element) { return element === this || this.children.some(child => child.contains(element)); }
  hasAttribute(name) { return this.attributes.has(name); }
  closest() {
    for (let element = this; element; element = element.parentElement) {
      if (["hidden", "inert", "aria-hidden='true'"].some(name => element.attributes.has(name))) return element;
    }
    return null;
  }
  matches(selector) {
    assert.equal(selector, ":disabled");
    if (this.disabled) return true;
    for (let element = this.parentElement; element; element = element.parentElement) {
      if (element.tagName === "FIELDSET" && element.disabled &&
        !element.children.find(child => child.tagName === "LEGEND")?.contains(this)) return true;
    }
    return false;
  }
  getClientRects() {
    if (!this.isConnected || (this.tagName === "INPUT" && this.type === "hidden")) return [];
    for (let element = this; element; element = element.parentElement) {
      if (element.display === "none" || element.attributes.has("hidden")) return [];
    }
    return [{}];
  }
  querySelectorAll() {
    return this.children.flatMap(child => [child, ...child.querySelectorAll()]).filter(element =>
      ["BUTTON", "INPUT", "SELECT", "TEXTAREA", "SUMMARY", "A", "IFRAME", "OBJECT", "EMBED"].includes(element.tagName) ||
      element.attributes.has("tabindex") || element.attributes.has("contenteditable='true'"));
  }
  focus() {
    if (!this.isConnected || this.matches(":disabled") || this.ownerDocument.activeElement === this) return;
    this.ownerDocument.activeElement = this;
    this.ownerDocument.dispatch("focusin", {});
  }
}

function fixture() {
  const listeners = new Map();
  const observers = [];
  const overflow = { value: "", priority: "" };
  const document = {
    addEventListener(type, callback) { (listeners.get(type) ?? listeners.set(type, new Set()).get(type)).add(callback); },
    removeEventListener(type, callback) { listeners.get(type)?.delete(callback); },
    dispatch(type, event) { for (const callback of [...(listeners.get(type) ?? [])]) callback(event); },
    defaultView: {
      getComputedStyle: element => ({ visibility: element.visibility }),
      MutationObserver: class {
        constructor(callback) { this.callback = callback; observers.push(this); }
        observe() { this.connected = true; }
        disconnect() { this.connected = false; }
      },
    },
  };
  document.body = new Element(document, "body");
  document.body.style = {
    getPropertyValue: () => overflow.value,
    getPropertyPriority: () => overflow.priority,
    setProperty(name, value, priority = "") { assert.equal(name, "overflow"); Object.assign(overflow, { value, priority }); },
    removeProperty(name) { assert.equal(name, "overflow"); Object.assign(overflow, { value: "", priority: "" }); },
  };
  const create = (tag = "button", options) => new Element(document, tag, options);
  const opener = document.body.append(create());
  const surface = document.body.append(create("div", { attributes: ["tabindex"] }));
  document.activeElement = opener;
  const key = (name, options = {}) => {
    const event = {
      key: name, defaultPrevented: false,
      preventDefault() { this.defaultPrevented = true; },
      stopPropagation() { this.stopped = true; }, ...options,
    };
    document.dispatch("keydown", event);
    return event;
  };
  return { document, surface, opener, create, key, overflow, listeners,
    flushMutations: () => observers.filter(observer => observer.connected).forEach(observer => observer.callback()) };
}

test("ModalSurface preserves semantic attributes and forces a programmatically focusable surface", () => {
  const markup = renderToStaticMarkup(React.createElement(ModalSurface, {
    as: "aside", role: "alertdialog", "aria-modal": true, "aria-labelledby": "title",
    className: "field-editor", tabIndex: 5, onDismiss() {}, focusKey: "warning", focusOnOpen: "first", returnFocusElement: null,
  }, React.createElement("h2", { id: "title" }, "Review settings")));
  assert.match(markup, /^<aside/);
  assert.match(markup, /role="alertdialog"/);
  assert.match(markup, /aria-modal="true"/);
  assert.match(markup, /aria-labelledby="title"/);
  assert.match(markup, /class="field-editor"/);
  assert.match(markup, /tabindex="-1"/i);
  assert.doesNotMatch(markup, /focusKey|onDismiss|focusOnOpen|returnFocusElement/);
});

test("tab stops exclude unavailable controls, honor details and fieldset exceptions, and order positive tabindex", () => {
  const { surface, create } = fixture();
  const button = surface.append(create());
  surface.append(create("input", { disabled: true }), create("input", { type: "hidden" }), create("a", { tabIndex: -1 }));
  surface.append(create("div", { attributes: ["hidden"] })).append(create());
  surface.append(create("div", { attributes: ["inert"] })).append(create());
  surface.append(create("div", { attributes: ["aria-hidden='true'"] })).append(create());
  surface.append(create("div", { display: "none" })).append(create());
  surface.append(create("button", { visibility: "hidden" }));
  const fieldset = surface.append(create("fieldset", { disabled: true }));
  const legendButton = fieldset.append(create("legend")).append(create());
  fieldset.append(create("input"));
  const details = surface.append(create("details"));
  const summary = details.append(create("summary"));
  details.append(create("button"), create("summary"));
  const textarea = surface.append(create("textarea"));
  const select = surface.append(create("select"));
  const positiveTwo = surface.append(create("button", { tabIndex: 2 }));
  const positiveOne = surface.append(create("button", { tabIndex: 1 }));
  assert.deepEqual(modalTabStops(surface), [positiveOne, positiveTwo, button, legendButton, summary, textarea, select]);
  details.attributes.add("open");
  assert.ok(modalTabStops(surface).includes(details.children[1]));
  assert.ok(!modalTabStops(surface).includes(details.children[2]));
});

test("radio groups use their checked tab stop and remain separate by form or name", () => {
  const { surface, create } = fixture();
  const radio = options => create("input", { type: "radio", name: "choice", ...options });
  const unchecked = surface.append(radio());
  const checked = surface.append(radio({ checked: true }));
  const separateForm = surface.append(radio({ form: {} }));
  const noName = surface.append(radio({ name: "" }));
  const anotherName = surface.append(radio({ name: "another" }));
  assert.deepEqual(modalTabStops(surface), [checked, separateForm, noName, anotherName]);
  checked.checked = false;
  assert.deepEqual(modalTabStops(surface), [unchecked, separateForm, noName, anotherName]);
});

test("initial focus and Tab stay inside the dialog in both directions", () => {
  const { document, surface, create, key, opener } = fixture();
  const first = surface.append(create("textarea"));
  const last = surface.append(create("select"));
  const close = mountModalFocus(surface, () => ({ onDismiss() {} }));
  assert.equal(document.activeElement, surface);
  assert.equal(key("Tab").defaultPrevented, true);
  assert.equal(document.activeElement, first);
  key("Tab", { shiftKey: true });
  assert.equal(document.activeElement, last);
  key("Tab");
  assert.equal(document.activeElement, first);
  key("Tab");
  assert.equal(document.activeElement, last);
  assert.equal(key("Tab", { ctrlKey: true }).defaultPrevented, false);
  close();
  assert.equal(document.activeElement, opener);
});

test("a modal with zero tab stops retains focus on its container", () => {
  const { document, surface, key } = fixture();
  const close = mountModalFocus(surface, () => ({ onDismiss() {}, focusOnOpen: "first" }));
  key("Tab");
  assert.equal(document.activeElement, surface);
  key("Tab", { shiftKey: true });
  assert.equal(document.activeElement, surface);
  close();
});

test("Escape uses fresh dismissal guards and callbacks and respects a handled child event", () => {
  const { surface, key } = fixture();
  let calls = 0;
  let options = { onDismiss: () => { calls += 1; }, canDismiss: () => false };
  const close = mountModalFocus(surface, () => options);
  const blocked = key("Escape");
  assert.equal(blocked.defaultPrevented, true);
  assert.equal(blocked.stopped, true);
  assert.equal(calls, 0);
  options = { onDismiss: () => { calls += 10; }, canDismiss: () => true };
  key("Escape", { defaultPrevented: true });
  key("Escape", { isComposing: true });
  assert.equal(calls, 0);
  key("Escape");
  assert.equal(calls, 10);
  close();
});

test("background focus is redirected to the last available target within the top modal", () => {
  const { document, surface, opener, create } = fixture();
  const button = surface.append(create());
  const close = mountModalFocus(surface, () => ({ onDismiss() {}, focusOnOpen: "first" }));
  assert.equal(document.activeElement, button);
  opener.focus();
  assert.equal(document.activeElement, button);
  button.remove();
  opener.focus();
  assert.equal(document.activeElement, surface);
  close();
});

test("only the nested top modal handles keys and closing it restores its opener in the parent", () => {
  const { document, surface, opener, create, key, overflow } = fixture();
  const parentButton = surface.append(create());
  let parentDismissed = 0;
  let childDismissed = 0;
  const closeParent = mountModalFocus(surface, () => ({ onDismiss: () => parentDismissed++, focusOnOpen: "first" }));
  const child = surface.append(create("div"));
  const cancel = child.append(create());
  let childBusy = true;
  const closeChild = mountModalFocus(child, () => ({ onDismiss: () => childDismissed++, canDismiss: () => !childBusy, focusOnOpen: "first" }));
  key("Escape");
  assert.equal(parentDismissed, 0);
  assert.equal(childDismissed, 0);
  key("Tab", { shiftKey: true });
  assert.equal(document.activeElement, cancel);
  childBusy = false;
  key("Escape");
  assert.equal(childDismissed, 1);
  closeChild();
  child.remove();
  assert.equal(document.activeElement, parentButton);
  assert.equal(overflow.value, "hidden");
  key("Escape");
  assert.equal(parentDismissed, 1);
  closeParent();
  assert.equal(document.activeElement, opener);
  assert.equal(overflow.value, "");
});

test("disabled nested opener falls back to the parent container", () => {
  const { document, surface, create } = fixture();
  const parentButton = surface.append(create());
  const closeParent = mountModalFocus(surface, () => ({ onDismiss() {}, focusOnOpen: "first" }));
  const child = surface.append(create("div"));
  const closeChild = mountModalFocus(child, () => ({ onDismiss() {} }));
  parentButton.disabled = true;
  closeChild();
  assert.equal(document.activeElement, surface);
  closeParent();
});

test("StrictMode-style replay and duplicate cleanup restore the original scroll style and listeners", () => {
  const { surface, overflow, listeners, document, opener } = fixture();
  Object.assign(overflow, { value: "scroll", priority: "important" });
  const options = () => ({ onDismiss() {} });
  const firstCleanup = mountModalFocus(surface, options);
  firstCleanup();
  firstCleanup();
  assert.deepEqual(overflow, { value: "scroll", priority: "important" });
  const finalCleanup = mountModalFocus(surface, options);
  assert.equal(listeners.get("keydown").size, 1);
  assert.equal(listeners.get("focusin").size, 1);
  finalCleanup();
  assert.equal(document.activeElement, opener);
  assert.equal(listeners.get("keydown").size, 0);
  assert.equal(listeners.get("focusin").size, 0);
  assert.deepEqual(overflow, { value: "scroll", priority: "important" });
});

test("parent-before-child cleanup preserves the final outside opener and scroll lock", () => {
  const { surface, document, opener, create, overflow } = fixture();
  surface.append(create());
  const closeParent = mountModalFocus(surface, () => ({ onDismiss() {}, focusOnOpen: "first" }));
  const child = surface.append(create("div"));
  const closeChild = mountModalFocus(child, () => ({ onDismiss() {} }));
  closeParent();
  assert.equal(document.activeElement, child);
  assert.equal(overflow.value, "hidden");
  closeChild();
  assert.equal(document.activeElement, opener);
  assert.equal(overflow.value, "");
});

test("simultaneously mounted child-before-parent keeps the child on top and remembers the original opener", () => {
  const { surface, document, opener, create } = fixture();
  const child = surface.append(create("div"));
  const closeChild = mountModalFocus(child, () => ({ onDismiss() {} }));
  const closeParent = mountModalFocus(surface, () => ({ onDismiss() {} }));
  assert.equal(document.activeElement, child);
  closeChild();
  assert.equal(document.activeElement, surface);
  closeParent();
  assert.equal(document.activeElement, opener);
});

test("removed or disabled active controls recover to the dialog container after a DOM update", () => {
  const { surface, document, create, flushMutations } = fixture();
  const button = surface.append(create());
  const close = mountModalFocus(surface, () => ({ onDismiss() {}, focusOnOpen: "first" }));
  button.remove();
  document.activeElement = document.body;
  flushMutations();
  assert.equal(document.activeElement, surface);
  const replacement = surface.append(create());
  replacement.focus();
  replacement.disabled = true;
  flushMutations();
  assert.equal(document.activeElement, surface);
  close();
  flushMutations();
  assert.notEqual(document.activeElement, surface);
});

test("stage refocus chooses the new first safe control without losing the original opener", () => {
  const { surface, document, opener, create } = fixture();
  const cancel = surface.append(create());
  const close = mountModalFocus(surface, () => ({ onDismiss() {}, focusOnOpen: "first" }));
  assert.equal(document.activeElement, cancel);
  cancel.remove();
  const goBack = surface.append(create());
  refocusModal(surface, "first");
  assert.equal(document.activeElement, goBack);
  close();
  assert.equal(document.activeElement, opener);
});

test("a removed or disabled final opener uses only the explicit safe fallback", async () => {
  for (const unavailable of ["removed", "disabled"]) {
    const { surface, document, opener, create } = fixture();
    const heading = document.body.append(create("h1", { attributes: ["tabindex"] }));
    const close = mountModalFocus(surface, () => ({ onDismiss() {}, restoreFocusFallback: () => heading }));
    if (unavailable === "removed") opener.remove();
    else opener.disabled = true;
    close();
    await Promise.resolve();
    assert.equal(document.activeElement, heading);
  }
});

test("initial focus prefers an explicitly marked safe control, skipping unavailable markers", () => {
  const { surface, document, create } = fixture();
  const detailsSummary = surface.append(create("summary"));
  const cancel = surface.append(create("button", { attributes: ["data-modal-initial-focus"] }));
  const close = mountModalFocus(surface, () => ({ onDismiss() {}, focusOnOpen: "first" }));
  assert.equal(document.activeElement, cancel);
  cancel.disabled = true;
  refocusModal(surface, "first");
  assert.equal(document.activeElement, detailsSummary);
  cancel.disabled = false;
  cancel.attributes.add("hidden");
  refocusModal(surface, "first");
  assert.equal(document.activeElement, detailsSummary);
  close();
});

test("a launcher reenabled later in the close commit is restored before the fallback", async () => {
  const { surface, document, opener, create } = fixture();
  const fallback = document.body.append(create("h1", { attributes: ["tabindex"] }));
  const close = mountModalFocus(surface, () => ({ onDismiss() {}, restoreFocusFallback: () => fallback }));
  opener.disabled = true;
  close();
  opener.disabled = false;
  await Promise.resolve();
  assert.equal(document.activeElement, opener);
});

test("pending final restoration cannot steal focus from a newer modal or deliberate focus", async () => {
  for (const action of ["new-modal", "new-focus"]) {
    const { surface, document, opener, create } = fixture();
    const close = mountModalFocus(surface, () => ({ onDismiss() {} }));
    opener.disabled = true;
    close();
    const target = document.body.append(create());
    const closeNext = action === "new-modal" ? mountModalFocus(target, () => ({ onDismiss() {} })) : null;
    if (!closeNext) target.focus();
    opener.disabled = false;
    await Promise.resolve();
    assert.equal(document.activeElement, target);
    closeNext?.();
  }
});

test("StrictMode replay preserves an opener that stays disabled until the real close", async () => {
  const { surface, document, opener } = fixture();
  const options = () => ({ onDismiss() {} });
  const initialCleanup = mountModalFocus(surface, options);
  opener.disabled = true;
  initialCleanup();
  const finalCleanup = mountModalFocus(surface, options);
  await Promise.resolve();
  assert.equal(document.activeElement, surface);
  finalCleanup();
  opener.disabled = false;
  await Promise.resolve();
  assert.equal(document.activeElement, opener);
});

test("body is not treated as a focusable original opener", async () => {
  const { surface, document, create } = fixture();
  const fallback = document.body.append(create("h1", { attributes: ["tabindex"] }));
  document.activeElement = document.body;
  const close = mountModalFocus(surface, () => ({ onDismiss() {}, restoreFocusFallback: () => fallback }));
  document.activeElement = document.body;
  close();
  await Promise.resolve();
  assert.equal(document.activeElement, fallback);
});

test("an explicitly captured launcher survives losing focus when disabled before the modal mounts", async () => {
  const { surface, document, opener, create } = fixture();
  opener.disabled = true;
  document.activeElement = document.body;
  let options = { onDismiss() {}, returnFocusElement: opener };
  const close = mountModalFocus(surface, () => options);
  options = { ...options, returnFocusElement: document.body.append(create()) };
  close();
  opener.disabled = false;
  await Promise.resolve();
  assert.equal(document.activeElement, opener, "later callback changes must not replace the original launcher");
});

test("an explicit disabled launcher survives StrictMode replay", async () => {
  const { surface, document, opener } = fixture();
  opener.disabled = true;
  document.activeElement = document.body;
  const options = () => ({ onDismiss() {}, returnFocusElement: opener });
  const firstCleanup = mountModalFocus(surface, options);
  firstCleanup();
  const finalCleanup = mountModalFocus(surface, options);
  await Promise.resolve();
  assert.equal(document.activeElement, surface);
  finalCleanup();
  opener.disabled = false;
  await Promise.resolve();
  assert.equal(document.activeElement, opener);
});
