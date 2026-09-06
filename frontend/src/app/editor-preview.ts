import { safeError, type SingleFlightGate } from "./workflow.js";

export interface PreviewRecord<T> {
  identity: string;
  response: T;
}

interface EditorPreviewRequest<T> {
  canPreview: boolean;
  gate: SingleFlightGate;
  identity: string;
  request: () => Promise<T>;
  setBusy: (value: "preview" | null) => void;
  setError: (value: ReturnType<typeof safeError> | null) => void;
  setSuccess: (value: boolean) => void;
  setPreviewRecord: (value: PreviewRecord<T> | null) => void;
}

// Only the common Preview lifecycle is shared. Each editor owns its Apply,
// refresh, and stale-preview policies.
export async function runEditorPreview<T>({
  canPreview, gate, identity, request, setBusy, setError, setSuccess, setPreviewRecord,
}: EditorPreviewRequest<T>): Promise<void> {
  if (!canPreview || !gate.tryEnter()) return;
  setBusy("preview"); setError(null); setSuccess(false);
  try {
    const response = await request();
    setPreviewRecord({ identity, response });
  } catch (caught) {
    setPreviewRecord(null); setError(safeError(caught));
  } finally {
    setBusy(null); gate.exit();
  }
}
