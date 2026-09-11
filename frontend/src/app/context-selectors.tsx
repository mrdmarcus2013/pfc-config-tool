import type { SupportPayorContext } from "../api/types";
import { payorContextKey } from "./payor-context.js";

export function ContextSelectors({ contexts, active, disabled, billingForm, onSelect }: {
  contexts: SupportPayorContext[]; active: SupportPayorContext;
  disabled: boolean; billingForm: string; onSelect: (key: string) => void;
}) {
  const available = contexts.some(c => payorContextKey(c) === payorContextKey(active))
    ? contexts : [active, ...contexts];
  const payors = [...new Map(available.map(c => [c.payor_guid, c])).values()];
  const plans = available.filter(c => c.payor_guid === active.payor_guid);
  return <dl className="context-grid">
    <div><dt><label htmlFor="context-payor">Payor</label></dt><dd>
      <select id="context-payor" value={active.payor_guid} disabled={disabled}
        onChange={e => onSelect(payorContextKey({ payor_guid: e.target.value, plan_guid: null }))}>
        {payors.map(c => <option key={c.payor_guid} value={c.payor_guid}>{c.payor_name}</option>)}
      </select>
    </dd></div>
    <div><dt><label htmlFor="context-plan">Plan</label></dt><dd>
      <select id="context-plan" value={payorContextKey(active)} disabled={disabled}
        onChange={e => onSelect(e.target.value)}>
        {!plans.some(c => c.plan_guid === null) && <option value={payorContextKey({ ...active, plan_guid: null })}>All Plans</option>}
        {plans.map((c, index) => <option key={payorContextKey(c)} value={payorContextKey(c)}>
          {c.plan_guid ? c.plan_name ?? `Plan ${index + 1}` : "All Plans"}
        </option>)}
      </select>
    </dd></div>
    <div><dt>Billing Form</dt><dd>{billingForm}</dd></div>
  </dl>;
}
