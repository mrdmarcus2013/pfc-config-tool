import { ModalSurface } from "./modal-surface.js";
import { remarksCurrentCache } from "./configuration-overview.js";
import { ConfigurationOwnerDetails, configurationSourceStatus } from "./configuration-owner-details.js";
import { useEffect, useRef, useState } from "react";
import { apiClient } from "../api/client.js";
import type {
  LineOfBusiness,
  RemarksChangeResponse,
  RemarksCurrentResponse,
} from "../api/types.js";
import type { ClaimFieldCatalogEntry } from "../types/claim-field.js";
import type { FrontendLaunchContext } from "../types/launch-context.js";
import { ClaimFieldPanelHeader } from "./claim-field-panel-header.js";
import { EditorFooter } from "./editor-footer.js";
import { runEditorPreview, type PreviewRecord } from "./editor-preview.js";
import {
  REMARKS_CUSTOM_REMARK_MAX_LENGTH,
  type RemarksIntent,
  remarksIdentity,
  remarksIntentFromCurrent,
  remarksIntentIsValid,
  remarksIntentMatchesCurrent,
  remarksRequest,
} from "./remarks.js";
import {
  currentPreview,
  editorActionState,
  previewAllowsApply,
  safeError,
  SingleFlightGate,
} from "./workflow.js";

interface RemarksEditorProps {
  field: ClaimFieldCatalogEntry;
  context: FrontendLaunchContext;
  lineOfBusiness: LineOfBusiness;
  onClose: () => void;
  supportDeveloperMode: boolean;
}

export function RemarksEditor({
  field,
  context,
  lineOfBusiness,
  onClose,
  supportDeveloperMode,
}: RemarksEditorProps) {
  const [current, setCurrent] = useState<RemarksCurrentResponse | null>(null);
  const [intent, setIntent] = useState<RemarksIntent>({
    mode: "DEFAULT",
    customRemark: "",
  });
  const [previewRecord, setPreviewRecord] = useState<PreviewRecord<RemarksChangeResponse> | null>(null);
  const [busy, setBusy] = useState<"preview" | "apply" | null>(null);
  const [error, setError] = useState<{ category: string; message: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [confirmationOpen, setConfirmationOpen] = useState(false);
  const [success, setSuccess] = useState(false);
  const gate = useRef(new SingleFlightGate());
  const currentRequest = {
    payor_guid: context.payor_guid,
    plan_guid: context.plan_guid,
  };
  const identity = remarksIdentity(context, lineOfBusiness, intent);
  const preview = currentPreview(previewRecord, identity);
  const valid = remarksIntentIsValid(intent);
  const dirty = current !== null && !remarksIntentMatchesCurrent(current, intent);
  const actionState = editorActionState({
    dirty,
    preview,
    busy,
    applyCompleted: success,
  });

  const initialize = (response: RemarksCurrentResponse) => {
    setCurrent(response);
    setIntent(remarksIntentFromCurrent(response));
    setPreviewRecord(null);
    setConfirmationOpen(false);
  };

  const loadCurrent = async (force = false) => {
    setLoading(true);
    setError(null);
    try {
      const response = await remarksCurrentCache.load(
        { ...currentRequest, field_number: "80" }, () => apiClient.remarksCurrent(currentRequest), force);
      initialize(response);
      return response;
    } catch (caught) {
      setCurrent(null);
      setError(safeError(caught));
      return null;
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadCurrent();
  }, [context.payor_guid, context.plan_guid, lineOfBusiness]);

  const update = (next: RemarksIntent) => {
    setIntent(next);
    setPreviewRecord(null);
    setError(null);
    setSuccess(false);
    setConfirmationOpen(false);
  };

  const runPreview = () => runEditorPreview({
    canPreview: dirty && valid, gate: gate.current, identity,
    request: () => apiClient.remarksPreview(remarksRequest(context, intent)),
    setBusy, setError, setSuccess, setPreviewRecord,
  });

  const runApply = async () => {
    if (!dirty || !valid || !previewAllowsApply(preview) || !gate.current.tryEnter()) return;
    const requested = intent;
    setBusy("apply");
    setConfirmationOpen(false);
    setError(null);
    try {
      await apiClient.remarksApply({
        ...remarksRequest(context, requested),
        expected_state_hash: preview!.state_hash,
      });
      setPreviewRecord(null);
      setSuccess(false);
      const refreshed = await loadCurrent(true);
      if (refreshed && remarksIntentMatchesCurrent(refreshed, requested)) {
        setSuccess(true);
      } else if (refreshed) {
        setError({
          category: "confirmation_failed",
          message: "The applied Remarks configuration could not be confirmed.",
        });
      }
    } catch (caught) {
      const safe = safeError(caught);
      setError(safe);
      if (safe.category === "stale_preview") setPreviewRecord(null);
    } finally {
      setBusy(null);
      gate.current.exit();
    }
  };

  const currentLabel = current?.mode === "CUSTOM" ? "Custom remark" : "Standard remarks";
  return (
    <div className="drawer-backdrop" role="presentation">
      <ModalSurface as="aside" className="field-editor" role="dialog" aria-modal="true" aria-labelledby="editor-title" onDismiss={onClose}>
        <ClaimFieldPanelHeader title="Remarks" onClose={onClose} />
        <div className="editor-body">
          <section className="editor-section">
            <h3>Remarks</h3>
            {loading && <p className="current-loading" role="status">Loading current configuration…</p>}
            {current && (
              <>
                <div className="configuration-stage current-configuration">
                  <h4 className="configuration-stage-title">Current configuration</h4>
                  <p><strong>{currentLabel}</strong></p>
                  {current.mode === "CUSTOM" && (
                    <dl className="configuration-summary">
                      <div><dt>Remark</dt><dd>{current.custom_remark}</dd></div>
                    </dl>
                  )}
                  {supportDeveloperMode && (
                    <details className="technical-details">
                      <summary>Technical details</summary>
                      {current.mode === "DEFAULT" && (
                        <p className="helper">Uses the inherited remarks configuration for the selected payor and plan.</p>
                      )}
                      <dl>
                        <div><dt>Canonical status</dt><dd>{configurationSourceStatus(current.configuration_owners)}</dd></div>
                        <div><dt>PFC GUID</dt><dd><code>{current.pfc_guid}</code></dd></div>
                        <ConfigurationOwnerDetails owners={current.configuration_owners} />
                        {Object.entries(current.debug).map(([key, value]) => (
                          <div key={key}><dt>{key}</dt><dd><code>{String(value ?? "")}</code></dd></div>
                        ))}
                      </dl>
                    </details>
                  )}
                </div>
                <div className="configuration-stage proposed-configuration">
                  <h4 className="configuration-stage-title">Proposed configuration</h4>
                  <fieldset>
                    <legend>Remarks configuration</legend>
                    <label className="choice">
                      <input type="radio" name="remarks-mode" checked={intent.mode === "DEFAULT"}
                        onChange={() => update({ ...intent, mode: "DEFAULT" })} />
                      <span>Use standard remarks</span>
                    </label>
                    <label className="choice">
                      <input type="radio" name="remarks-mode" checked={intent.mode === "CUSTOM"}
                        onChange={() => update({ ...intent, mode: "CUSTOM" })} />
                      <span>Use a custom remark</span>
                    </label>
                  </fieldset>
                  {intent.mode === "CUSTOM" && (
                    <label className="remarks-input">
                      <span>Custom remark</span>
                      <textarea aria-label="Custom remark" value={intent.customRemark}
                        maxLength={REMARKS_CUSTOM_REMARK_MAX_LENGTH}
                        onChange={(event) => update({ ...intent, customRemark: event.target.value })} />
                      <small className="character-counter" aria-live="polite">
                        {intent.customRemark.length} / {REMARKS_CUSTOM_REMARK_MAX_LENGTH}
                      </small>
                      {!valid && <small className="validation-message">Enter a custom remark before Preview.</small>}
                    </label>
                  )}
                  <p className={dirty ? "dirty-indicator" : "unchanged-indicator"}>
                    {dirty ? "Proposed configuration differs from the current configuration." : "Matches current configuration."}
                  </p>
                </div>
              </>
            )}
          </section>
          {error && <div className={`notice error ${error.category === "stale_preview" ? "stale" : ""}`} role="alert"><strong>Unable to complete request</strong><p>{error.message}</p></div>}
          {success && <div className="notice success" role="status"><strong>Configuration applied</strong><p>The requested Remarks configuration was applied and refreshed.</p></div>}
          {preview && <div className="configuration-stage preview-stage"><h4 className="configuration-stage-title">Preview</h4><p>{preview.summary}</p>{supportDeveloperMode && <details className="technical-details"><summary>Technical details</summary><dl><div><dt>State hash</dt><dd><code>{preview.state_hash}</code></dd></div></dl></details>}</div>}
        </div>
        <EditorFooter actionState={actionState}
          previewDisabled={busy !== null || loading || current === null || !dirty || !valid}
          previewLabel={busy === "preview" ? "Previewing…" : "Preview"}
          onDismiss={onClose} onPreview={runPreview}
          onApply={() => setConfirmationOpen(true)} />
        {confirmationOpen && <div className="confirmation-backdrop" role="presentation"><ModalSurface className="confirmation" role="alertdialog" aria-modal="true" aria-labelledby="remarks-confirmation-title" onDismiss={() => setConfirmationOpen(false)} focusOnOpen="first"><h3 id="remarks-confirmation-title">Apply configuration?</h3><p><strong>{field.fieldNumber} — Remarks</strong></p><p>{intent.mode === "DEFAULT" ? "Use standard remarks" : intent.customRemark}</p><div className="confirmation-actions"><button type="button" className="secondary-button" data-modal-initial-focus onClick={() => setConfirmationOpen(false)}>Cancel</button><button type="button" className="primary-button" onClick={runApply}>Apply</button></div></ModalSurface></div>}
      </ModalSurface>
    </div>
  );
}
