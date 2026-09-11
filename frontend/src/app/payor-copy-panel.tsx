import { useEffect, useRef, useState } from "react";
import { apiClient, ApiClientError } from "../api/client.js";
import type { PayorCopyRequest, PayorCopyResponse } from "../api/types";
import type { FrontendLaunchContext } from "../types/launch-context";
import { safeError } from "./workflow.js";
import { ModalSurface } from "./modal-surface.js";
import { safeCopyTechnicalErrorMessage } from "./copy-errors.js";

export const copyErrorPresentation = (error: unknown) => ({
  message: safeError(error).message,
  technicalMessage: error instanceof ApiClientError
    ? safeCopyTechnicalErrorMessage(error.category, error.message) : null,
});

export function CopyErrorMessage({ error, supportDeveloperMode = false }: {
  error: ReturnType<typeof copyErrorPresentation>; supportDeveloperMode?: boolean;
}) {
  return <>
    <p>{error.message}</p>
    {supportDeveloperMode && error.technicalMessage && <details className="technical-details">
      <summary>Technical details</summary><p>{error.technicalMessage}</p>
    </details>}
  </>;
}

export function CopyReview({ result, destination, supportDeveloperMode = false }: {
  result: PayorCopyResponse; destination: string; supportDeveloperMode?: boolean;
}) {
  return <section aria-label="Copy preview" className="copy-review">
    <h3>{result.status === "APPLIED" ? "Copy completed" : "Preview for " + destination}</h3>
    <p>Billing form: {result.billing_form_code} · Line of Business: {result.line_of_business === "HOME_HEALTH" ? "Home Health" : "Hospice"}</p>
    <p>{result.status === "NO_CHANGE" ? "This payor already matches. No changes are needed."
      : result.status === "APPLIED" ? "The payor and its current plan contexts were verified. All changes were saved together."
        : "Review the complete replacement before accepting. Source settings will remain unchanged."}</p>
    <dl className="copy-counts">
      <div><dt>{result.status === "APPLIED" ? "Settings copied" : "Settings to copy"}</dt><dd>{result.records_copied}</dd></div>
      <div><dt>Matching settings kept</dt><dd>{result.records_kept}</dd></div>
      <div><dt>Existing settings removed</dt><dd>{result.records_removed}</dd></div>
      <div><dt>Plan overrides included in removals</dt><dd>{result.plan_records_removed}</dd></div>
      <div><dt>Payor/plan configurations reviewed</dt><dd>{result.contexts.length}</dd></div>
    </dl>
    {result.status !== "NO_CHANGE" && result.template_contexts_updated > 0 && result.records_copied === 0 && result.records_removed === 0 &&
      <p>{result.status === "APPLIED" ? "The destination configuration was updated. Its individual settings already matched."
        : "Configuration changes are required even though the individual settings already match. Review the affected payor and plan settings below."}</p>}
    {result.records_normalized > 0 && <p>{result.records_normalized} copied settings require standard safety adjustments. These adjustments apply only to the destination copies.</p>}
    <h4>Destination payor and plans</h4>
    <ul>{result.contexts.map(c => <li key={c.pfc_guid}><strong>{c.label}</strong></li>)}</ul>
    <details><summary>Review individual settings ({result.changes.length})</summary>
      <table className="copy-details"><thead><tr><th>Action</th><th>Setting</th></tr></thead>
        <tbody>{result.changes.map((c,i) => <tr key={i}><td>{{ COPY: "Copy", REMOVE: "Remove", KEEP: "Keep" }[c.action]}</td><td>{c.label}</td></tr>)}</tbody>
      </table>
    </details>
    {supportDeveloperMode && <details className="technical-details">
      <summary>Technical details</summary>
      <dl><div><dt>Template associations updated</dt><dd>{result.template_contexts_updated} contexts</dd></div></dl>
      <ul>{result.contexts.map(c => <li key={c.pfc_guid}><strong>{c.label}</strong> — {c.templates_changed ? "Adopt source templates" : "Templates already match"}
        <div>Form template: {c.form_template_before} → {result.source_form_template}</div>
        <div>User form template: {c.user_template_before} → {result.source_user_template}</div>
      </li>)}</ul>
      <table className="copy-details"><thead><tr><th>Setting</th><th>Configuration level</th></tr></thead>
        <tbody>{result.changes.map((c,i) => <tr key={i}><td>{c.label}</td><td>{c.level}</td></tr>)}</tbody>
      </table>
    </details>}
  </section>;
}

export function PayorCopyPanel({ source, sourceLabel, onClose, onApplied, returnFocusElement, supportDeveloperMode = false }: {
  source: FrontendLaunchContext; sourceLabel: string;
  onClose: () => void; onApplied: (destination: string) => void;
  returnFocusElement?: HTMLElement | null;
  supportDeveloperMode?: boolean;
}) {
  const [destination, setDestination] = useState("");
  const [preview, setPreview] = useState<PayorCopyResponse | null>(null);
  const [accepted, setAccepted] = useState(false);
  const [busy, setBusy] = useState<"preview" | "apply" | null>(null);
  const [error, setError] = useState<ReturnType<typeof copyErrorPresentation> | null>(null);
  const gate = useRef(false);
  const [options, setOptions] = useState<{ payor_guid: string; payor_name: string }[]>([]);
  const [loadingDestinations, setLoadingDestinations] = useState(true);
  const [destinationError, setDestinationError] = useState<ReturnType<typeof copyErrorPresentation> | null>(null);
  const [retry, setRetry] = useState(0);
  const label = options.find(c => c.payor_guid === destination)?.payor_name ?? "";
  const applied = preview?.status === "APPLIED";
  const request: PayorCopyRequest = { source_payor_guid: source.payor_guid,
    source_plan_guid: source.plan_guid, destination_payor_guid: destination, audit_user: source.audit_user };

  useEffect(() => {
    let cancelled = false;
    setLoadingDestinations(true); setDestinationError(null); setOptions([]);
    setDestination(""); setPreview(null); setAccepted(false); setError(null);
    void apiClient.eligibleCopyDestinations({ source_payor_guid: source.payor_guid,
      source_plan_guid: source.plan_guid, audit_user: source.audit_user }).then(result => {
      if (!cancelled) setOptions(result.destinations);
    }).catch(caught => {
      if (!cancelled) setDestinationError(copyErrorPresentation(caught));
    }).finally(() => { if (!cancelled) setLoadingDestinations(false); });
    return () => { cancelled = true; };
  }, [source.payor_guid, source.plan_guid, source.audit_user, retry]);

  const run = async (apply: boolean) => {
    if (gate.current || !destination || (apply && (!accepted || preview?.status !== "READY"))) return;
    gate.current = true; setBusy(apply ? "apply" : "preview"); setError(null);
    try {
      const result = apply
        ? await apiClient.applyPayorCopy({ ...request, expected_state_hash: preview!.state_hash })
        : await apiClient.previewPayorCopy(request);
      setPreview(result); setAccepted(false);
      if (apply) onApplied(destination);
    } catch (caught) {
      setPreview(null); setAccepted(false); setError(copyErrorPresentation(caught));
    } finally { gate.current = false; setBusy(null); }
  };

  return <div className="drawer-backdrop">
    <ModalSurface className="field-editor copy-panel" role="dialog" aria-modal="true" aria-labelledby="copy-title"
      onDismiss={onClose} canDismiss={() => !gate.current} returnFocusElement={returnFocusElement}>
      <header className="editor-header"><div><span className="eyebrow">Payor configuration</span><h2 id="copy-title">Copy Payor Settings</h2></div>
        <button className="icon-button" aria-label="Close copy panel" disabled={!!busy} onClick={onClose}>×</button></header>
      <div className="editor-body">
        <section className="configuration-stage"><h3>Copy from</h3><p><strong>{sourceLabel}</strong></p>
          <p>{source.plan_guid ? "Copy the loaded payor and plan configuration." : "Copy the loaded payor configuration."}</p>
          {supportDeveloperMode && <details className="technical-details"><summary>Technical details</summary>
            <p>{source.plan_guid ? "Selected plan settings take precedence over this payor's settings." : "Copy this payor's settings and template associations."}</p>
            <p>The destination payor and every current plan context will adopt the source template associations.</p>
          </details>}
        </section>
        <label className="copy-destination">Copy to payor
          <select value={destination} disabled={!!busy || applied || loadingDestinations || !!destinationError || !options.length} onChange={e => { setDestination(e.target.value); setPreview(null); setAccepted(false); setError(null); }}>
            <option value="">Select destination payor</option>
            {options.map(c => <option key={c.payor_guid} value={c.payor_guid}>{c.payor_name}</option>)}
          </select>
        </label>
        {loadingDestinations && <p role="status">Checking eligible destination payors…</p>}
        {destinationError && <div role="alert"><CopyErrorMessage error={destinationError} supportDeveloperMode={supportDeveloperMode} /><button className="secondary-button" onClick={() => setRetry(value => value + 1)}>Retry</button></div>}
        {!loadingDestinations && !destinationError && options.length === 0 && <p role="status">No eligible destination payors are available for this source configuration.</p>}
        <p>The billing form and Line of Business must match. The destination payor and all its plans will use the copied configuration.</p>
        <div className="notice warning"><strong>Destination plan overrides will be cleared.</strong><p>This replaces the destination configuration for the payor and all its plans. Users can add plan-specific changes again afterward.</p></div>
        {error && <div className="notice error" role="alert"><strong>Copy could not be completed</strong><CopyErrorMessage error={error} supportDeveloperMode={supportDeveloperMode} /></div>}
        {busy && <p role="status">{busy === "apply" ? "Copying and verifying all destination contexts…" : "Comparing the complete source and destination configuration…"}</p>}
        {preview && <CopyReview result={preview} destination={label} supportDeveloperMode={supportDeveloperMode} />}
        {preview?.status === "READY" && <label className="copy-confirm"><input type="checkbox" checked={accepted} disabled={!!busy} onChange={e => setAccepted(e.target.checked)} />
          I accept replacing {label}'s configuration for the payor and all its plans, including clearing existing plan-specific customizations.
        </label>}
      </div>
      <footer className="editor-footer copy-footer">
        <button className="secondary-button" disabled={!!busy} onClick={onClose}>{applied ? "Close" : "Cancel"}</button>
        {!applied && <button className="secondary-button" disabled={!!busy || !destination} onClick={() => { void run(false); }}>Preview</button>}
        {!applied && <button className="primary-button" disabled={!!busy || !accepted || preview?.status !== "READY"} onClick={() => { void run(true); }}>Accept and Copy</button>}
      </footer>
    </ModalSurface>
  </div>;
}
