import { clearCurrentConfigurations } from "./configuration-overview.js";
import { safeError } from "./workflow.js";

export type LineOfBusinessOperation = "save" | "preview" | "apply";

// One lifetime per mounted control. A new lifetime also owns a new request gate,
// so an old completion cannot release a newer request after a remount.
export class LineOfBusinessRequestScope {
  private lifetime: symbol | null = null;
  private request: symbol | null = null;

  activate(): () => void {
    const lifetime = Symbol();
    this.lifetime = lifetime;
    this.request = null;
    return () => {
      if (this.lifetime === lifetime) {
        this.lifetime = null;
        this.request = null;
      }
    };
  }

  begin(): { isCurrent: () => boolean; finish: () => void } | null {
    if (this.lifetime === null || this.request !== null) return null;
    const lifetime = this.lifetime;
    const request = Symbol();
    this.request = request;
    const isCurrent = () => this.lifetime === lifetime && this.request === request;
    return { isCurrent, finish: () => { if (isCurrent()) this.request = null; } };
  }
}

interface LineOfBusinessRequest<T> {
  scope: LineOfBusinessRequestScope;
  operation: LineOfBusinessOperation;
  request: () => Promise<T>;
  onSuccess: (response: T) => void;
  onSaved: () => void;
  setBusy: (operation: LineOfBusinessOperation | null) => void;
  setError: (error: ReturnType<typeof safeError> | null) => void;
  onError?: (error: ReturnType<typeof safeError>) => void;
}

export async function runLineOfBusinessRequest<T>({
  scope, operation, request, onSuccess, onSaved, setBusy, setError, onError = setError,
}: LineOfBusinessRequest<T>): Promise<void> {
  const pending = scope.begin();
  if (!pending) return;
  setBusy(operation); setError(null);
  try {
    const response = await request();
    if (operation !== "preview") {
      // The original payor was saved even if its control has since unmounted.
      clearCurrentConfigurations();
      onSaved();
    }
    if (pending.isCurrent()) onSuccess(response);
  } catch (caught) {
    if (pending.isCurrent()) onError(safeError(caught));
  } finally {
    if (pending.isCurrent()) setBusy(null);
    pending.finish();
  }
}
