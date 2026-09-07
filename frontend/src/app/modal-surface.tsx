import { useCallback, useLayoutEffect, useRef, type HTMLAttributes } from "react";
import { mountModalFocus, refocusModal, type ModalFocusOptions } from "./modal-focus.js";

interface ModalSurfaceProps extends HTMLAttributes<HTMLElement>, ModalFocusOptions {
  as?: "aside" | "div";
  focusKey?: string;
}

export function ModalSurface({
  as: Surface = "div", onDismiss, canDismiss, focusOnOpen = "dialog",
  restoreFocusFallback, returnFocusElement, focusKey, ...attributes
}: ModalSurfaceProps) {
  const surface = useRef<HTMLElement | null>(null);
  const options = useRef<ModalFocusOptions>({ onDismiss, canDismiss, focusOnOpen, restoreFocusFallback, returnFocusElement });
  const lastFocusKey = useRef(focusKey);
  const setSurface = useCallback((element: HTMLElement | null) => { surface.current = element; }, []);
  useLayoutEffect(() => {
    options.current = { onDismiss, canDismiss, focusOnOpen, restoreFocusFallback, returnFocusElement };
  });
  useLayoutEffect(() => {
    const element = surface.current;
    if (element) return mountModalFocus(element, () => ({
      ...options.current,
      restoreFocusFallback: options.current.restoreFocusFallback ??
        (() => element.ownerDocument.querySelector<HTMLElement>("[data-modal-return-target]")),
    }));
  }, []);
  useLayoutEffect(() => {
    if (focusKey !== lastFocusKey.current && surface.current) refocusModal(surface.current, focusOnOpen);
    lastFocusKey.current = focusKey;
  }, [focusKey, focusOnOpen]);
  return <Surface {...attributes} tabIndex={-1} ref={setSurface} />;
}
