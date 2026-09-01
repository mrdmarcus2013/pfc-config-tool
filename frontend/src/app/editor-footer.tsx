import type { EditorActionState } from "./workflow.js";
import { PREVIEW_REQUIRED_MESSAGE } from "./workflow.js";

interface EditorFooterProps {
  actionState: EditorActionState;
  previewDisabled: boolean;
  previewLabel: string;
  onDismiss: () => void;
  onPreview: () => void;
  onApply: () => void;
}

export function EditorFooter({
  actionState,
  previewDisabled,
  previewLabel,
  onDismiss,
  onPreview,
  onApply,
}: EditorFooterProps) {
  return (
    <footer className="editor-footer">
      <button type="button" className="secondary-button" onClick={onDismiss}>
        {actionState.dismissLabel}
      </button>
      {!actionState.configurationCompleted && (
        <div className="editor-action-region">
          {actionState.previewRequired && (
            <p className="editor-action-guidance" role="status">{PREVIEW_REQUIRED_MESSAGE}</p>
          )}
          <div className="editor-action-buttons">
            {actionState.previewVisible && (
              <button
                type="button"
                className="secondary-button preview-button"
                disabled={previewDisabled}
                onClick={onPreview}
              >
                {previewLabel}
              </button>
            )}
            <button
              type="button"
              className="primary-button"
              disabled={!actionState.applyEnabled}
              onClick={onApply}
            >
              Apply Changes
            </button>
          </div>
        </div>
      )}
    </footer>
  );
}
