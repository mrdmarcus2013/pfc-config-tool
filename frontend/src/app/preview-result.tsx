import type { ConfigurationResponse } from "../api/types";
import type { PublicOptionCode } from "../data/configuration-capabilities";
import { supportPreviewPresentation } from "./presentation.js";

interface PreviewResultProps {
  optionCode: PublicOptionCode;
  preview: ConfigurationResponse;
  supportDeveloperMode: boolean;
}

export function PreviewResult({ optionCode, preview, supportDeveloperMode }: PreviewResultProps) {
  const presentation = supportPreviewPresentation(optionCode, preview);
  return (
    <section className="preview-card" aria-live="polite">
      <h4 className="preview-section-label">Preview</h4>
      <span className="status-chip">{presentation.statusLabel}</span>
      <h3>{presentation.heading}</h3>
      <dl className="summary-list">
        {presentation.requestedConfiguration.map((item) => (
          <div key={item.label}><dt>{item.label}</dt><dd>{item.value}</dd></div>
        ))}
      </dl>
      <div className="support-summary">
        <h4>Summary</h4>
        <p>{presentation.message}</p>
        {preview.status === "NO_CHANGE" && <p className="no-change-note">No database changes are required.</p>}
      </div>
      {presentation.changes.length > 0 && <div className="affected-components">
        <h4>What will change</h4>
        <ul>{presentation.changes.map((change) => <li key={change}>{change}</li>)}</ul>
      </div>}
      {supportDeveloperMode && <details className="technical-details">
        <summary>Technical details</summary>
        <dl>
          <div><dt>Public option code</dt><dd><code>{preview.option_code}</code></dd></div>
          <div><dt>PFC GUID</dt><dd><code>{preview.pfc_guid ?? "Not returned"}</code></dd></div>
          <div><dt>Preview state hash</dt><dd><code className="hash">{preview.state_hash}</code></dd></div>
          <div><dt>API summary</dt><dd>{preview.summary}</dd></div>
        </dl>
        {preview.debug_changes.length > 0 && <div className="database-diagnostics">
          <h4>Database diagnostics</h4>
          {preview.debug_changes.map((change) => <p key={`technical-${change.operation_order}`}>
            <code>{change.operation_code}</code> · target {change.target_identifier ?? "not returned"} · field {change.field_number ?? "not returned"}
          </p>)}
        </div>}
      </details>}
    </section>
  );
}
