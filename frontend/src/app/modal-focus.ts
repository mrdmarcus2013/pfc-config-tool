export interface ModalFocusOptions {
  onDismiss: () => void;
  canDismiss?: () => boolean;
  focusOnOpen?: "dialog" | "first";
  returnFocusElement?: HTMLElement | null;
  restoreFocusFallback?: () => HTMLElement | null;
}

interface ModalEntry {
  surface: HTMLElement;
  options: () => ModalFocusOptions;
  opener: HTMLElement | null;
  lastFocused: HTMLElement | null;
}

interface ModalStack {
  entries: ModalEntry[];
  redirecting: boolean;
  release: () => void;
}

const stacks = new WeakMap<Document, ModalStack>();
const lifetimes = new WeakMap<Document, number>();
const pendingRestores = new WeakMap<Document, { surface: HTMLElement; opener: HTMLElement | null }>();
const candidateSelector = "a[href],area[href],button,input,select,textarea,summary,[tabindex],iframe,object,embed,[contenteditable='true'],audio[controls],video[controls]";

function available(element: HTMLElement): boolean {
  if (!element.isConnected || element.matches(":disabled") || element.closest("[hidden],[inert],[aria-hidden='true']")) return false;
  const style = element.ownerDocument.defaultView?.getComputedStyle(element);
  if (style?.visibility === "hidden" || style?.visibility === "collapse" || element.getClientRects().length === 0) return false;
  // A closed details exposes only its first summary and that summary's content.
  for (let parent = element.parentElement; parent; parent = parent.parentElement) {
    if (parent.tagName === "DETAILS" && !parent.hasAttribute("open")) {
      const summary = Array.from(parent.children).find(child => child.tagName === "SUMMARY");
      if (!summary?.contains(element)) return false;
    }
  }
  return true;
}

export function modalTabStops(surface: HTMLElement): HTMLElement[] {
  const candidates = Array.from(surface.querySelectorAll<HTMLElement>(candidateSelector)).filter(element => {
    if (element.tabIndex < 0 || !available(element)) return false;
    if (element.tagName === "SUMMARY" && element.parentElement?.tagName === "DETAILS" && !element.hasAttribute("tabindex")) {
      return Array.from(element.parentElement.children).find(child => child.tagName === "SUMMARY") === element;
    }
    return true;
  });
  return candidates.filter(element => {
    if (element.tagName !== "INPUT") return true;
    const radio = element as HTMLInputElement;
    if (radio.type !== "radio" || !radio.name) return true;
    const group = candidates.filter(candidate => candidate.tagName === "INPUT" &&
      (candidate as HTMLInputElement).type === "radio" &&
      (candidate as HTMLInputElement).name === radio.name &&
      (candidate as HTMLInputElement).form === radio.form) as HTMLInputElement[];
    return (group.find(candidate => candidate.checked) ?? group[0]) === radio;
  }).sort((a, b) => (a.tabIndex > 0 ? a.tabIndex : Infinity) - (b.tabIndex > 0 ? b.tabIndex : Infinity));
}

function focus(element: HTMLElement | null): boolean {
  if (!element || !available(element)) return false;
  element.focus({ preventScroll: true });
  return element.ownerDocument.activeElement === element;
}

function focusInside(entry: ModalEntry, preference: "dialog" | "first" = "dialog"): void {
  if (preference === "first") {
    const stops = modalTabStops(entry.surface);
    const initial = stops.find(element => element.hasAttribute("data-modal-initial-focus"));
    if (focus(initial ?? stops[0] ?? null)) return;
  }
  focus(entry.surface);
}

function top(stack: ModalStack): ModalEntry | undefined {
  return stack.entries[stack.entries.length - 1];
}

function createStack(document: Document): ModalStack {
  const stack: ModalStack = { entries: [], redirecting: false, release: () => {} };
  const bodyStyle = document.body.style;
  const oldOverflow = bodyStyle.getPropertyValue("overflow");
  const oldPriority = bodyStyle.getPropertyPriority("overflow");
  bodyStyle.setProperty("overflow", "hidden");

  const keydown = (event: KeyboardEvent) => {
    const entry = top(stack);
    if (!entry || event.defaultPrevented || event.isComposing) return;
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      const options = entry.options();
      if (options.canDismiss?.() !== false) options.onDismiss();
    } else if (event.key === "Tab" && !event.altKey && !event.ctrlKey && !event.metaKey) {
      event.preventDefault();
      const stops = modalTabStops(entry.surface);
      const index = stops.indexOf(document.activeElement as HTMLElement);
      const next = index < 0 ? (event.shiftKey ? stops.length - 1 : 0) : (index + (event.shiftKey ? -1 : 1) + stops.length) % stops.length;
      if (!focus(stops[next] ?? null)) focusInside(entry);
    }
  };
  const focusin = () => {
    const entry = top(stack);
    if (!entry || stack.redirecting) return;
    const active = document.activeElement as HTMLElement | null;
    if (active && entry.surface.contains(active)) {
      entry.lastFocused = active;
      return;
    }
    stack.redirecting = true;
    try {
      if (!entry.lastFocused || !entry.surface.contains(entry.lastFocused) || !focus(entry.lastFocused)) focusInside(entry);
    } finally {
      stack.redirecting = false;
    }
  };
  document.addEventListener("keydown", keydown);
  document.addEventListener("focusin", focusin);
  stack.release = () => {
    document.removeEventListener("keydown", keydown);
    document.removeEventListener("focusin", focusin);
    if (oldOverflow) bodyStyle.setProperty("overflow", oldOverflow, oldPriority);
    else bodyStyle.removeProperty("overflow");
    stacks.delete(document);
  };
  return stack;
}

/** Refocus an existing active modal without replacing its opener or stack entry. */
export function refocusModal(surface: HTMLElement, preference: "dialog" | "first" = "dialog"): void {
  const stack = stacks.get(surface.ownerDocument);
  const entry = stack && top(stack);
  if (entry?.surface === surface) focusInside(entry, preference);
}

/** Attach one modal lifetime. All callbacks are read when needed, not captured at opening. */
export function mountModalFocus(surface: HTMLElement, options: () => ModalFocusOptions): () => void {
  const document = surface.ownerDocument;
  lifetimes.set(document, (lifetimes.get(document) ?? 0) + 1);
  let stack = stacks.get(document);
  if (!stack) {
    stack = createStack(document);
    stacks.set(document, stack);
  }
  const pendingRestore = pendingRestores.get(document);
  const active = document.activeElement as HTMLElement | null;
  const explicitOpener = options().returnFocusElement;
  const opener = pendingRestore && active && pendingRestore.surface.contains(active)
    ? pendingRestore.opener : active === document.body || active === document.documentElement ? null : active;
  pendingRestores.delete(document);
  const entry: ModalEntry = {
    surface, options, opener: explicitOpener ?? opener, lastFocused: null,
  };
  // React mounts child layout effects first. A simultaneously mounted parent
  // belongs below its descendants and inherits their original outside opener.
  const descendantIndex = stack.entries.findIndex(item => surface.contains(item.surface));
  if (descendantIndex >= 0) {
    entry.opener = explicitOpener ?? stack.entries[descendantIndex].opener;
    stack.entries.splice(descendantIndex, 0, entry);
  } else {
    stack.entries.push(entry);
    focusInside(entry, options().focusOnOpen);
  }
  const activeStack = stack;
  const Observer = document.defaultView?.MutationObserver;
  const observer = Observer && new Observer(() => {
    if (top(activeStack) !== entry) return;
    const active = document.activeElement as HTMLElement | null;
    if (!active || !surface.contains(active) || !available(active)) focusInside(entry);
  });
  observer?.observe(surface, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ["disabled", "hidden", "inert", "aria-hidden", "open", "style", "class", "tabindex"],
  });

  let mounted = true;
  return () => {
    if (!mounted) return;
    mounted = false;
    observer?.disconnect();
    const wasTop = top(activeStack) === entry;
    activeStack.entries.splice(activeStack.entries.indexOf(entry), 1);
    // Parent-before-child cleanup must not leave a child pointing to an opener
    // inside the removed parent when it eventually closes.
    for (const remaining of activeStack.entries) {
      if (remaining.opener && surface.contains(remaining.opener)) remaining.opener = entry.opener;
    }
    const next = top(activeStack);
    if (!next) activeStack.release();
    if (!wasTop) return;
    if (next) {
      if (!entry.opener || !next.surface.contains(entry.opener) || !focus(entry.opener)) focusInside(next);
    } else if (!focus(entry.opener)) {
      // React may re-enable the launcher later in this same commit. Recheck
      // before falling back, but never steal focus from a newer modal or action.
      const lifetime = lifetimes.get(document);
      const activeAtClose = document.activeElement;
      const pending = { surface, opener: entry.opener };
      pendingRestores.set(document, pending);
      queueMicrotask(() => {
        if (pendingRestores.get(document) === pending) pendingRestores.delete(document);
        if (lifetimes.get(document) !== lifetime || stacks.has(document)) return;
        const active = document.activeElement;
        if (active !== activeAtClose && active !== document.body && active?.isConnected) return;
        if (!focus(entry.opener)) focus(entry.options().restoreFocusFallback?.() ?? null);
      });
    }
  };
}
