import type { ProviderTaxonomySelection } from "../data/configuration-capabilities";

export const TAXONOMY_CODE_LENGTH = 10;
export const normalizeTaxonomyCode = (value: string): string => value.trim().toUpperCase();
export const validTaxonomyCode = (value: string): boolean => /^[A-Z0-9]{10}$/.test(value);

export function TaxonomyControls({ selection, code, busy, onSelection, onCode }: {
  selection: ProviderTaxonomySelection;
  code: string;
  busy: boolean;
  onSelection: (selection: ProviderTaxonomySelection) => void;
  onCode: (code: string) => void;
}) {
  return <fieldset disabled={busy}>
    <legend>Provider Taxonomy</legend>
    <div className="inline-choices">
      {(["no", "yes", "custom"] as const).map((value) => (
        <label className="choice compact" key={value}>
          <input type="radio" name="provider-taxonomy" checked={selection === value}
            onChange={() => onSelection(value)} />
          <span>{value === "custom" ? "Custom" : value === "yes" ? "Standard" : "None"}</span>
        </label>
      ))}
    </div>
    <p className="helper">None omits taxonomy. Standard uses the provider's taxonomy. Custom uses the code you enter.</p>
    {selection === "custom" && <div className="taxonomy-code-entry">
      <label htmlFor="taxonomy-code">Taxonomy code</label>
      <input id="taxonomy-code" type="text" maxLength={TAXONOMY_CODE_LENGTH} required
        value={code} autoComplete="off" spellCheck={false}
        aria-describedby="taxonomy-code-help" aria-invalid={!validTaxonomyCode(code)}
        onChange={(event) => onCode(normalizeTaxonomyCode(event.target.value))} />
      <p id="taxonomy-code-help" className="helper">Enter a 10-character taxonomy code using letters and numbers.</p>
    </div>}
  </fieldset>;
}
