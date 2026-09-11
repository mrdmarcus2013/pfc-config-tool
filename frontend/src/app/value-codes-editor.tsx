import { ModalSurface } from "./modal-surface.js";
import { useEffect, useRef, useState } from "react";
import { apiClient } from "../api/client.js";
import type {
  LineOfBusiness, ValueCodesChangeResponse, ValueCodesCurrentResponse,
} from "../api/types";
import type { ClaimFieldCatalogEntry } from "../types/claim-field";
import type { FrontendLaunchContext } from "../types/launch-context";
import { valueCodesCurrentCache } from "./configuration-overview.js";
import { ConfigurationOwnerDetails, configurationSourceStatus } from "./configuration-owner-details.js";
import { currentPreview, editorActionState, previewAllowsApply, safeError, SingleFlightGate } from "./workflow.js";
import { runEditorPreview, type PreviewRecord } from "./editor-preview.js";
import { EditorFooter } from "./editor-footer.js";
import { ClaimFieldPanelHeader } from "./claim-field-panel-header.js";
import { ValueCodesProposal } from "./value-codes-proposal.js";
import {
  emptyValueCodeSelections, valueCodeSelectionIdentity, valueCodesDraftFromCurrent,
  valueCodesDraftIsComplete, valueCodesDraftMatchesCurrent, valueCodesDraftSummary,
  valueCodesCurrentSummary, valueCodesRequestSelections, type ValueCodesDraft,
} from "./value-codes.js";

interface ValueCodesEditorProps {
  field: ClaimFieldCatalogEntry;
  context: FrontendLaunchContext;
  lineOfBusiness: LineOfBusiness;
  onClose: () => void;
  supportDeveloperMode: boolean;
}

export function ValueCodesEditor({ field, context, lineOfBusiness, onClose, supportDeveloperMode }: ValueCodesEditorProps) {
  const [current, setCurrent] = useState<ValueCodesCurrentResponse | null>(null);
  const [draft, setDraft] = useState<ValueCodesDraft>(emptyValueCodeSelections);
  const [previewRecord, setPreviewRecord] = useState<PreviewRecord<ValueCodesChangeResponse> | null>(null);
  const [busy, setBusy] = useState<"preview" | "apply" | null>(null);
  const [error, setError] = useState<{ category: string; message: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [confirmationOpen, setConfirmationOpen] = useState(false);
  const [success, setSuccess] = useState(false);
  const gate = useRef(new SingleFlightGate());
  const request = { payor_guid: context.payor_guid, plan_guid: context.plan_guid };
  const valid = valueCodesDraftIsComplete(draft);
  const identity = valueCodeSelectionIdentity(context, lineOfBusiness, draft) + "|OFF";
  const preview = currentPreview(previewRecord, identity);
  const dirty = current !== null && !valueCodesDraftMatchesCurrent(current, draft);
  const actionState = editorActionState({ dirty, preview, busy, applyCompleted: success });

  const initialize = (response: ValueCodesCurrentResponse) => {
    setCurrent(response); setDraft(valueCodesDraftFromCurrent(response)); setPreviewRecord(null);
    setConfirmationOpen(false);
  };
  const loadCurrent = async (force = false, initializeIntent = true) => {
    setLoading(true); if (initializeIntent) setError(null);
    try {
      const response = await valueCodesCurrentCache.load({ ...request, field_number: "39-41" }, () => apiClient.valueCodesCurrent(request), force);
      if (initializeIntent) initialize(response);
      else setCurrent(response);
      return response;
    }
    catch (caught) { setCurrent(null); setError(safeError(caught)); return null; }
    finally { setLoading(false); }
  };
  useEffect(() => { void loadCurrent(); }, [context.payor_guid, context.plan_guid, lineOfBusiness]);

  const update = (next: ValueCodesDraft) => {
    setDraft(next); setPreviewRecord(null); setError(null); setSuccess(false); setConfirmationOpen(false);
  };
  const runPreview = () => runEditorPreview({
    canPreview: dirty && valid, gate: gate.current, identity,
    request: () => apiClient.valueCodesPreview({ ...request, selections: valueCodesRequestSelections(draft),
      empty_selection_behavior: "OFF", audit_user: context.audit_user }),
    setBusy, setError, setSuccess, setPreviewRecord,
  });
  const runApply = async () => {
    if (!dirty || !valid || !previewAllowsApply(preview) || !gate.current.tryEnter()) return;
    const requested = valueCodesRequestSelections(draft);
    setBusy("apply"); setConfirmationOpen(false); setError(null);
    try {
      await apiClient.valueCodesApply({ ...request, selections: requested, empty_selection_behavior: "OFF",
        audit_user: context.audit_user, expected_state_hash: preview!.state_hash });
      setPreviewRecord(null); setSuccess(false);
      const refreshed = await loadCurrent(true);
      if (refreshed && valueCodesDraftMatchesCurrent(refreshed, requested)) setSuccess(true);
      else if (refreshed) setError({ category: "confirmation_failed", message: "The applied Value Codes configuration could not be confirmed." });
    } catch (caught) {
      const safe = safeError(caught); setError(safe);
      if (safe.category === "stale_preview") {
        setPreviewRecord(null);
        await loadCurrent(true, false);
      }
    } finally { setBusy(null); gate.current.exit(); }
  };
  const summary = valueCodesDraftSummary(lineOfBusiness, draft);
  return <div className="drawer-backdrop" role="presentation">
    <ModalSurface as="aside" className="field-editor" role="dialog" aria-modal="true" aria-labelledby="editor-title" onDismiss={onClose}>
      <ClaimFieldPanelHeader title="Value Codes" onClose={onClose} />
      <div className="editor-body"><section className="editor-section"><h3>Value Codes</h3>
        {loading && <p className="current-loading" role="status">Loading current configuration…</p>}
        {current && <><div className="configuration-stage current-configuration">
          <h4 className="configuration-stage-title">Current configuration</h4>
          <p><strong>{valueCodesCurrentSummary(current)}</strong></p>
          {supportDeveloperMode && <details className="technical-details"><summary>Technical details</summary><dl>
            <div><dt>Canonical status</dt><dd>{configurationSourceStatus(current.configuration_owners)}</dd></div>
            <div><dt>Resolved configuration</dt><dd>{current.display_summary}</dd></div>
            <div><dt>PFC GUID</dt><dd><code>{current.pfc_guid}</code></dd></div>
                        <ConfigurationOwnerDetails owners={current.configuration_owners} />
            {Object.entries(current.debug).map(([key, value]) => <div key={key}><dt>{key}</dt><dd><code>{String(value ?? "")}</code></dd></div>)}
          </dl></details>}
        </div><ValueCodesProposal current={current} draft={draft} disabled={busy !== null || loading} onChange={update} /></>}
        {error && <div className={`notice error ${error.category === "stale_preview" ? "stale" : ""}`} role="alert"><strong>Unable to complete request</strong><p>{error.message}</p></div>}
        {success && <div className="notice success" role="status"><strong>Configuration applied</strong><p>The requested Value Codes configuration was applied and refreshed.</p></div>}
        {preview && <div className="configuration-stage preview-stage"><h4 className="configuration-stage-title">Preview</h4><p>{preview.summary}</p>
          {supportDeveloperMode && <details className="technical-details"><summary>Technical details</summary><dl><div><dt>State hash</dt><dd><code>{preview.state_hash}</code></dd></div></dl></details>}
        </div>}
      </section></div>
      <EditorFooter actionState={actionState} previewDisabled={busy !== null || loading || current === null || !dirty || !valid}
        previewLabel={busy === "preview" ? "Previewing…" : "Preview"} onDismiss={onClose} onPreview={runPreview} onApply={() => setConfirmationOpen(true)}/>
      {confirmationOpen && <div className="confirmation-backdrop" role="presentation"><ModalSurface className="confirmation" role="alertdialog" aria-modal="true" aria-labelledby="value-codes-confirmation-title" onDismiss={() => setConfirmationOpen(false)} focusOnOpen="first"><h3 id="value-codes-confirmation-title">Apply configuration?</h3><p><strong>{field.fieldNumber} — Value Codes</strong></p><p>{summary}</p><div className="confirmation-actions"><button type="button" className="secondary-button" data-modal-initial-focus onClick={() => setConfirmationOpen(false)}>Cancel</button><button type="button" className="primary-button" onClick={runApply}>Apply</button></div></ModalSurface></div>}
    </ModalSurface></div>;
}
