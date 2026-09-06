import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { apiClient } from "../api/client.js";
import type {
  LineOfBusiness, LineOfBusinessChangeResponse, LineOfBusinessCurrentResponse,
} from "../api/types";
import type { FrontendLaunchContext } from "../types/launch-context";
import { lineOfBusinessLabel, lobApplyRequest, lobPreviewAfterError, otherLineOfBusiness } from "./line-of-business.js";
import { LineOfBusinessRequestScope, runLineOfBusinessRequest } from "./line-of-business-request.js";
import { SUPPORT_DEVELOPER_MODE } from "./environment.js";

interface LineOfBusinessControlProps {
  context: FrontendLaunchContext;
  current: LineOfBusinessCurrentResponse | null;
  loading: boolean;
  disabled: boolean;
  onChanged: (lineOfBusiness: LineOfBusiness, message: string) => void;
  onSaved: () => void;
  onChangeStarted: () => void;
}

export function LineOfBusinessControl({ context, current, loading, disabled, onChanged, onSaved, onChangeStarted }: LineOfBusinessControlProps) {
  const saved = current?.line_of_business ?? null;
  const [selection, setSelection] = useState<LineOfBusiness | null>(null);
  const [stage, setStage] = useState<"warning" | "confirm" | null>(null);
  const [preview, setPreview] = useState<LineOfBusinessChangeResponse | null>(null);
  const [busy, setBusy] = useState<"save" | "preview" | "apply" | null>(null);
  const [error, setError] = useState<{ category: string; message: string } | null>(null);
  const requestScope = useRef(new LineOfBusinessRequestScope());

  useLayoutEffect(() => requestScope.current.activate(), []);
  useEffect(() => { if (saved) setSelection(saved); }, [saved]);

  const saveInitial = async () => {
    if (!selection || saved) return;
    await runLineOfBusinessRequest({
      scope: requestScope.current, operation: "save", setBusy, setError, onSaved,
      request: () => apiClient.lineOfBusinessSave({
        payor_guid: context.payor_guid,
        line_of_business: selection,
        audit_user: context.audit_user,
      }),
      onSuccess: response => onChanged(response.line_of_business, `${lineOfBusinessLabel(response.line_of_business)} was saved.`),
    });
  };

  const beginChange = () => {
    if (!saved) return;
    onChangeStarted();
    setSelection(otherLineOfBusiness(saved));
    setPreview(null); setError(null); setStage("warning");
  };

  const runChangePreview = async () => {
    if (!saved || !selection || selection === saved) return;
    await runLineOfBusinessRequest({
      scope: requestScope.current, operation: "preview", setBusy, setError, onSaved,
      request: () => apiClient.lineOfBusinessPreviewChange({
        payor_guid: context.payor_guid,
        requested_line_of_business: selection,
      }),
      onSuccess: response => {
        setPreview(response);
        setStage(response.status === "NO_CHANGE" ? null : "confirm");
      },
    });
  };

  const applyChange = async () => {
    if (!preview || preview.status !== "CHANGES_REQUIRED") return;
    await runLineOfBusinessRequest({
      scope: requestScope.current, operation: "apply", setBusy, setError, onSaved,
      request: () => apiClient.lineOfBusinessApplyChange(
        lobApplyRequest(context, preview),
      ),
      onSuccess: response => {
        setPreview(null); setStage(null);
        onChanged(response.requested_line_of_business,
          `Line of Business changed to ${lineOfBusinessLabel(response.requested_line_of_business)}. Managed claim-field customizations were reset for all plans.`);
      },
      onError: safe => {
        setPreview((value) => lobPreviewAfterError(value, safe.category));
        setError(safe);
        if (safe.category === "stale_preview") setStage("warning");
      },
    });
  };

  return (
    <section className="lob-card" aria-labelledby="lob-heading">
      <div className="lob-heading-row">
        <div><span className="eyebrow">Payor-level setting</span><h2 id="lob-heading">Line of Business</h2></div>
        {saved && <button type="button" className="secondary-button" disabled={disabled} onClick={beginChange}>Change Line of Business</button>}
      </div>
      {loading && <p className="lob-status" role="status">Loading Line of Business…</p>}
      {!loading && current && <>
        <fieldset className="lob-choices" disabled={disabled || saved !== null || busy !== null}>
          {(["HOME_HEALTH", "HOSPICE"] as LineOfBusiness[]).map((value) => <label className="choice compact" key={value}>
            <input type="radio" name="line-of-business" checked={(saved ?? selection) === value} onChange={() => setSelection(value)} />
            <span>{lineOfBusinessLabel(value)}</span>
          </label>)}
        </fieldset>
        {!saved && <button type="button" className="primary-button" disabled={disabled || !selection || busy !== null} onClick={saveInitial}>{busy === "save" ? "Saving…" : "Save Line of Business"}</button>}
        {saved && <p className="lob-status">Saved for this payor. Every plan uses {lineOfBusinessLabel(saved)}.</p>}
      </>}
      {error && <div className="notice error" role="alert"><strong>Line of Business was not changed</strong><p>{error.category === "stale_preview" ? "The reset scope changed after it was reviewed. Continue to run a new preview." : error.message}</p></div>}

      {stage === "warning" && saved && selection && <div className="modal-backdrop" role="presentation"><div className="lob-modal" role="alertdialog" aria-modal="true" aria-labelledby="lob-warning-title">
        <h3 id="lob-warning-title">Change Line of Business?</h3>
        {error?.category === "stale_preview" && <div className="notice error" role="alert"><strong>Run a new reset preview</strong><p>The reset scope changed after it was reviewed. Continue to refresh the preview before applying.</p></div>}
        <p>Changing the Line of Business from {lineOfBusinessLabel(saved)} to {lineOfBusinessLabel(selection)} will remove all payor-specific claim field customizations managed by this tool and restore those fields to their standard default configuration.</p>
        <p><strong>This applies to all plans under this payor.</strong></p>
        <div className="confirmation-actions"><button type="button" className="secondary-button" onClick={() => setStage(null)}>Cancel</button><button type="button" className="primary-button" disabled={busy !== null} onClick={runChangePreview}>{busy === "preview" ? "Reviewing…" : "Continue"}</button></div>
      </div></div>}

      {stage === "confirm" && preview && <div className="modal-backdrop" role="presentation"><div className="lob-modal" role="alertdialog" aria-modal="true" aria-labelledby="lob-confirm-title">
        <h3 id="lob-confirm-title">Confirm Reset</h3>
        <p>Reset all managed claim field customizations for all plans under this payor and change Line of Business to {lineOfBusinessLabel(preview.requested_line_of_business)}?</p>
        <p><strong>{preview.affected_managed_target_count} customized claim-field component(s) will be reset.</strong></p>
        {SUPPORT_DEVELOPER_MODE && <details className="technical-details"><summary>Technical reset details</summary><dl>
          <div><dt>Preview hash</dt><dd><code>{preview.preview_state_hash}</code></dd></div>
          <div><dt>Managed targets</dt><dd>{preview.managed_target_count}</dd></div>
          <div><dt>Managed records</dt><dd>{preview.managed_her_count}</dd></div>
          <div><dt>Managed fields</dt><dd>{preview.managed_hef_count}</dd></div>
        </dl></details>}
        <div className="confirmation-actions"><button type="button" className="secondary-button" onClick={() => setStage("warning")}>Go Back</button><button type="button" className="primary-button" disabled={busy !== null} onClick={applyChange}>{busy === "apply" ? "Resetting…" : `Reset Fields and Change to ${lineOfBusinessLabel(preview.requested_line_of_business)}`}</button></div>
      </div></div>}
    </section>
  );
}
