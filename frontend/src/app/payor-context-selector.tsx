import type { SupportPayorContext } from "../api/types";
import { payorContextKey, payorContextLabel } from "./payor-context.js";

interface PayorContextSelectorProps {
  contexts: SupportPayorContext[];
  activeContext: SupportPayorContext;
  loading: boolean;
  switching: boolean;
  error: string | null;
  onSelect: (selectionKey: string) => void;
}

export function PayorContextSelector({
  contexts,
  activeContext,
  loading,
  switching,
  error,
  onSelect,
}: PayorContextSelectorProps) {
  const activeKey = payorContextKey(activeContext);
  const hasActiveOption = contexts.some(
    (context) => payorContextKey(context) === activeKey,
  );
  return (
    <section className="support-context-selector" aria-labelledby="support-context-heading">
      <div>
        <span className="eyebrow">Tier 2 support</span>
        <h2 id="support-context-heading">Payor Context</h2>
      </div>
      <label>
        <span>Select payor</span>
        <select
          value={activeKey}
          disabled={loading || switching || contexts.length === 0}
          onChange={(event) => onSelect(event.target.value)}
        >
          {!hasActiveOption && (
            <option value={activeKey}>{payorContextLabel(activeContext)}</option>
          )}
          {contexts.map((context) => (
            <option key={payorContextKey(context)} value={payorContextKey(context)}>
              {payorContextLabel(context)}
            </option>
          ))}
        </select>
      </label>
      <p className="support-context-status" role="status">
        {loading
          ? "Loading available payors…"
          : switching
            ? "Resolving the selected payor…"
            : "Plan, PFC, and template assignments are resolved together by Oracle."}
      </p>
      {error && <div className="notice error" role="alert"><strong>Payor was not changed</strong><p>{error}</p></div>}
    </section>
  );
}
