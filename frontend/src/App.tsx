import { useEffect, useMemo, useRef, useState } from "react";
import { apiClient } from "./api/client";
import type {
  ConfigurationResponse, CurrentConfigurationResponse, OptionField,
} from "./api/types";
import {
  currentConfigurationCache, currentConfigurationRequest, currentOptionDiffers,
  selectionsFromCurrent,
} from "./app/current-state";
import {
  catalogFieldIsAvailable, currentPreview, previewAfterError,
  editorActionState, previewAllowsApply, previewIdentity, previewRequest, providerTaxonomyOption,
  safeError, serviceFacilityOption, SingleFlightGate,
} from "./app/workflow";
import { EditorFooter } from "./app/editor-footer";
import {
  fieldEditorTitle, technicalDetailsEnabled,
} from "./app/presentation";
import { PreviewResult } from "./app/preview-result";
import { CLAIM_FIELD_CATALOG } from "./data/claim-field-catalog";
import type {
  ProviderTaxonomySelection, PublicOptionCode, ServiceFacilityAddress, ServiceFacilityMode,
} from "./data/configuration-capabilities";
import { UI_DEMO_DISPLAY_CONTEXT, UI_DEMO_LAUNCH_CONTEXT } from "./data/ui-demo-context";
import type { ClaimFieldCatalogEntry, ClaimFieldSection } from "./types/claim-field";
import type { FrontendLaunchContext } from "./types/launch-context";

const CAPABILITY_DESCRIPTION = {
  "service-facility": "Service Facility reporting settings",
  "provider-taxonomy": "Provider Taxonomy reporting",
} as const;

type FieldGroupLayout =
  | "billing"
  | "patient-details"
  | "admission"
  | "codes"
  | "tail"
  | "services"
  | "insurance"
  | "diagnosis"
  | "procedures"
  | "providers"
  | "other";

interface ClaimFieldGroupDefinition {
  id: string;
  label?: string;
  from: number;
  through: number;
  layout: FieldGroupLayout;
}

interface ClaimSectionDefinition {
  name: ClaimFieldSection;
  range: string;
  groups: readonly ClaimFieldGroupDefinition[];
}

const CLAIM_SECTION_LAYOUT: readonly ClaimSectionDefinition[] = [
  { name: "Billing Details", range: "1–7", groups: [
    { id: "billing-details", from: 1, through: 7, layout: "billing" },
  ] },
  { name: "Patient", range: "8–30", groups: [
    { id: "patient-details", from: 8, through: 11, layout: "patient-details" },
    { id: "admission", label: "Admission", from: 12, through: 17, layout: "admission" },
    { id: "condition-codes", label: "Condition Codes", from: 18, through: 28, layout: "codes" },
    { id: "patient-other", from: 29, through: 30, layout: "tail" },
  ] },
  { name: "Admissions & Occurrences", range: "31–41", groups: [
    { id: "occurrence", label: "Occurrence", from: 31, through: 34, layout: "codes" },
    { id: "occurrence-span", label: "Occurrence Span", from: 35, through: 36, layout: "codes" },
    { id: "occurrence-other", from: 37, through: 38, layout: "tail" },
    { id: "value-codes", label: "Value Codes", from: 39, through: 41, layout: "codes" },
  ] },
  { name: "Services", range: "42–49", groups: [
    { id: "services", from: 42, through: 49, layout: "services" },
  ] },
  { name: "Insurance", range: "50–65", groups: [
    { id: "payer-billing", label: "Payer & Billing", from: 50, through: 57, layout: "insurance" },
    { id: "subscriber", label: "Subscriber", from: 58, through: 65, layout: "insurance" },
  ] },
  { name: "Diagnosis & Procedure Codes", range: "66–75", groups: [
    { id: "diagnosis-codes", label: "Diagnosis Codes", from: 66, through: 73, layout: "diagnosis" },
    { id: "procedure-codes", label: "Procedure Codes", from: 74, through: 75, layout: "procedures" },
  ] },
  { name: "Providers", range: "76–79", groups: [
    { id: "providers", from: 76, through: 79, layout: "providers" },
  ] },
  { name: "Other", range: "80–81", groups: [
    { id: "other", from: 80, through: 81, layout: "other" },
  ] },
];

const baseFieldNumber = (field: ClaimFieldCatalogEntry) =>
  Number.parseInt(field.fieldNumber, 10);

const SUPPORT_DEVELOPER_MODE = technicalDetailsEnabled(
  import.meta.env.VITE_ENABLE_TECHNICAL_DETAILS,
);

const SERVICE_MODE_LABEL: Record<ServiceFacilityMode, string> = {
  always: "Always report service facility",
  conditional: "Only report service facility when care location is not HOME",
  never: "Never report service facility",
};

interface PreviewRecord { identity: string; response: ConfigurationResponse }
interface FieldEditorProps {
  field: ClaimFieldCatalogEntry;
  context: FrontendLaunchContext;
  onClose: () => void;
  supportDeveloperMode: boolean;
}

function FieldEditor({ field, context, onClose, supportDeveloperMode }: FieldEditorProps) {
  const [serviceMode, setServiceMode] = useState<ServiceFacilityMode>("never");
  const [serviceAddress, setServiceAddress] = useState<ServiceFacilityAddress>("no");
  const [taxonomy, setTaxonomy] = useState<ProviderTaxonomySelection>("no");
  const [previewRecord, setPreviewRecord] = useState<PreviewRecord | null>(null);
  const [busy, setBusy] = useState<"preview" | "apply" | null>(null);
  const [error, setError] = useState<{ category: string; message: string } | null>(null);
  const [confirmationOpen, setConfirmationOpen] = useState(false);
  const [success, setSuccess] = useState(false);
  const [currentConfig, setCurrentConfig] = useState<CurrentConfigurationResponse | null>(null);
  const [currentLoading, setCurrentLoading] = useState(true);
  const [currentError, setCurrentError] = useState<{ category: string; message: string } | null>(null);
  const requestGate = useRef(new SingleFlightGate());

  const fieldNumber = field.fieldNumber as "77" | "81";
  const currentRequest = currentConfigurationRequest(context, fieldNumber);

  const optionCode: PublicOptionCode = field.capabilityKey === "service-facility"
    ? serviceFacilityOption(serviceMode, serviceAddress)
    : providerTaxonomyOption(taxonomy);
  const identity = previewIdentity(context, optionCode);
  const preview = currentPreview(previewRecord, identity);
  const dirty = currentOptionDiffers(currentConfig, optionCode);
  const actionState = editorActionState({
    dirty, preview, busy, applyCompleted: success,
  });
  const selectionSummary = field.capabilityKey === "service-facility"
    ? `${SERVICE_MODE_LABEL[serviceMode]}; address: ${serviceAddress === "yes" ? "Yes" : "No"}`
    : `Provider Taxonomy: ${taxonomy === "yes" ? "Yes" : "No"}`;

  const initializeFromCurrent = (response: CurrentConfigurationResponse) => {
    const selections = selectionsFromCurrent(response);
    setCurrentConfig(response);
    setServiceMode(selections.serviceMode);
    setServiceAddress(selections.serviceAddress);
    setTaxonomy(selections.taxonomy);
    setPreviewRecord(null);
    setConfirmationOpen(false);
  };

  const loadCurrent = async (force = false, initializeSelections = true) => {
    setCurrentLoading(true);
    setCurrentError(null);
    try {
      const response = await currentConfigurationCache.load(
        currentRequest,
        () => apiClient.current(currentRequest),
        force,
      );
      if (initializeSelections) initializeFromCurrent(response);
      else setCurrentConfig(response);
      return response;
    } catch (caught) {
      setCurrentConfig(null);
      setCurrentError(safeError(caught));
      return null;
    } finally {
      setCurrentLoading(false);
    }
  };

  useEffect(() => {
    let active = true;
    setCurrentLoading(true);
    setCurrentError(null);
    void currentConfigurationCache.load(
      currentRequest,
      () => apiClient.current(currentRequest),
    ).then((response) => {
      if (!active) return;
      initializeFromCurrent(response);
    }).catch((caught) => {
      if (!active) return;
      setCurrentConfig(null);
      setCurrentError(safeError(caught));
    }).finally(() => {
      if (active) setCurrentLoading(false);
    });
    return () => { active = false; };
  }, [context.payor_guid, context.plan_guid, fieldNumber]);

  const invalidate = () => {
    setPreviewRecord(null);
    setError(null);
    setSuccess(false);
    setConfirmationOpen(false);
  };

  const runPreview = async () => {
    if (!dirty || !requestGate.current.tryEnter()) return;
    setBusy("preview"); setError(null); setSuccess(false);
    try {
      const response = await apiClient.preview(previewRequest(context, optionCode));
      setPreviewRecord({ identity, response });
    } catch (caught) {
      setPreviewRecord(null); setError(safeError(caught));
    } finally { setBusy(null); requestGate.current.exit(); }
  };

  const runApply = async () => {
    if (!dirty || !previewAllowsApply(preview) || !requestGate.current.tryEnter()) return;
    setBusy("apply"); setConfirmationOpen(false); setError(null);
    try {
      await apiClient.apply({
        ...previewRequest(context, optionCode), expected_state_hash: preview!.state_hash,
      });
      setSuccess(false); setPreviewRecord(null);
      currentConfigurationCache.invalidate(currentRequest);
      const refreshed = await loadCurrent(true);
      if (refreshed?.effective_option_code === optionCode) {
        setSuccess(true);
      } else if (refreshed !== null) {
        setError({
          category: "confirmation_failed",
          message: "The applied configuration could not be confirmed against the refreshed current state.",
        });
      }
    } catch (caught) {
      const safe = safeError(caught);
      setPreviewRecord((record) => previewAfterError(record, safe.category));
      setError(safe);
      if (safe.category === "stale_preview") {
        currentConfigurationCache.invalidate(currentRequest);
        const refreshed = await loadCurrent(true, false);
        if (refreshed?.effective_option_code === optionCode) setError(null);
      }
    } finally { setBusy(null); requestGate.current.exit(); }
  };

  return (
    <div className="drawer-backdrop" role="presentation">
      <aside className="field-editor" role="dialog" aria-modal="true" aria-labelledby="editor-title">
        <header className="editor-header">
          <div><span className="eyebrow">Claim field configuration</span><h2 id="editor-title">{fieldEditorTitle(field)}</h2></div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close editor">×</button>
        </header>

        <div className="editor-body">
          <section className="editor-section">
            <h3>{field.capabilityKey === "service-facility" ? "Service Facility Reporting" : "Provider Taxonomy"}</h3>
            {currentLoading && <p className="current-loading" role="status">Loading current configurationâ€¦</p>}
            {currentError && (
              <div className="notice error" role="alert">
                <strong>Current configuration could not be loaded</strong>
                <p>{currentError.message}</p>
                <button type="button" className="link-button" onClick={() => { void loadCurrent(true); }}>Try Again</button>
              </div>
            )}
            {currentConfig && (
              <>
                <div className="configuration-stage current-configuration">
                  <h4 className="configuration-stage-title">Current configuration</h4>
                  <dl className="configuration-summary">
                    {field.capabilityKey === "service-facility" ? (
                      <>
                        <div><dt>Reporting</dt><dd>{SERVICE_MODE_LABEL[currentConfig.display.mode!.toLowerCase() as ServiceFacilityMode]}</dd></div>
                        <div><dt>Report address</dt><dd>{currentConfig.display.report_address === "Y" ? "Yes" : "No"}</dd></div>
                      </>
                    ) : (
                      <div><dt>Report Provider Taxonomy</dt><dd>{currentConfig.display.enabled ? "Yes" : "No"}</dd></div>
                    )}
                  </dl>
                  {supportDeveloperMode && (
                    <details className="technical-details">
                      <summary>Technical details</summary>
                      <dl>
                        <div><dt>Effective option</dt><dd><code>{currentConfig.effective_option_code}</code></dd></div>
                        <div><dt>PFC GUID</dt><dd><code>{currentConfig.pfc_guid}</code></dd></div>
                        {currentConfig.canonical !== null && <div><dt>Canonical</dt><dd>{currentConfig.canonical ? "Yes" : "No"}</dd></div>}
                      </dl>
                    </details>
                  )}
                </div>

                <div className="configuration-stage proposed-configuration">
                  <h4 className="configuration-stage-title">Proposed configuration</h4>
                  {field.capabilityKey === "service-facility" ? (
                    <>
                      <fieldset>
                        <legend>When should service facility information be reported?</legend>
                        {(Object.keys(SERVICE_MODE_LABEL) as ServiceFacilityMode[]).map((mode) => (
                          <label className="choice" key={mode}>
                            <input type="radio" name="service-mode" checked={serviceMode === mode} onChange={() => {
                              setServiceMode(mode); if (mode === "never") setServiceAddress("no"); invalidate();
                            }} />
                            <span>{SERVICE_MODE_LABEL[mode]}</span>
                          </label>
                        ))}
                      </fieldset>
                      <fieldset disabled={serviceMode === "never"}>
                        <legend>Report address?</legend>
                        <div className="inline-choices">
                          {(["yes", "no"] as ServiceFacilityAddress[]).map((address) => (
                            <label className="choice compact" key={address}>
                              <input type="radio" name="service-address" checked={serviceAddress === address} onChange={() => { setServiceAddress(address); invalidate(); }} />
                              <span>{address === "yes" ? "Yes" : "No"}</span>
                            </label>
                          ))}
                        </div>
                        {serviceMode === "never" && <p className="helper">Address reporting is off when service facility reporting is never used.</p>}
                      </fieldset>
                    </>
                  ) : (
                    <fieldset>
                      <legend>Report Provider Taxonomy?</legend>
                      <div className="inline-choices">
                        {(["yes", "no"] as ProviderTaxonomySelection[]).map((selection) => (
                          <label className="choice compact" key={selection}>
                            <input type="radio" name="provider-taxonomy" checked={taxonomy === selection} onChange={() => { setTaxonomy(selection); invalidate(); }} />
                            <span>{selection === "yes" ? "Yes" : "No"}</span>
                          </label>
                        ))}
                      </div>
                    </fieldset>
                  )}
                  <p className={dirty ? "dirty-indicator" : "unchanged-indicator"}>
                    {dirty ? "Proposed configuration differs from the current configuration." : "Matches current configuration."}
                  </p>
                </div>
              </>
            )}
          </section>

          {error && (
            <div className={`notice error ${error.category === "stale_preview" ? "stale" : ""}`} role="alert">
              <strong>{error.category === "stale_preview" ? "Configuration changed since the preview." : "Unable to complete request"}</strong>
              <p>{error.category === "stale_preview" ? "The configuration was modified after it was reviewed. Preview the proposal before applying." : error.message}</p>
            </div>
          )}
          {success && <div className="notice success" role="status"><strong>Configuration applied</strong><p>The requested configuration was applied and checked against the current state.</p></div>}

          {preview && <PreviewResult optionCode={optionCode} preview={preview} supportDeveloperMode={supportDeveloperMode} />}
        </div>

        <EditorFooter
          actionState={actionState}
          previewDisabled={busy !== null || currentLoading || currentConfig === null || !dirty}
          previewLabel={busy === "preview" ? "Previewing…" : "Preview"}
          onDismiss={onClose}
          onPreview={runPreview}
          onApply={() => setConfirmationOpen(true)}
        />

        {confirmationOpen && <div className="confirmation-backdrop" role="presentation"><div className="confirmation" role="alertdialog" aria-modal="true" aria-labelledby="confirmation-title">
          <h3 id="confirmation-title">Apply configuration?</h3>
          <p><strong>Field {field.fieldNumber} — {field.label}</strong></p><p>{selectionSummary}</p>
          <div className="confirmation-actions"><button type="button" className="secondary-button" onClick={() => setConfirmationOpen(false)}>Cancel</button><button type="button" className="primary-button" disabled={busy !== null} onClick={runApply}>Apply</button></div>
        </div></div>}
      </aside>
    </div>
  );
}

export function App() {
  const [optionFields, setOptionFields] = useState<OptionField[]>([]);
  const [metadataError, setMetadataError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [selectedField, setSelectedField] = useState<ClaimFieldCatalogEntry | null>(null);

  const loadOptions = async () => {
    setLoading(true); setMetadataError(null);
    try { setOptionFields((await apiClient.options()).fields); }
    catch (caught) { setOptionFields([]); setMetadataError(safeError(caught).message); }
    finally { setLoading(false); }
  };
  useEffect(() => { void loadOptions(); }, []);

  const normalizedSearch = search.trim().toLowerCase();
  const visibleFields = useMemo(() => CLAIM_FIELD_CATALOG.filter((field) =>
    !normalizedSearch || field.fieldNumber.toLowerCase().includes(normalizedSearch) || field.label.toLowerCase().includes(normalizedSearch),
  ), [normalizedSearch]);
  return (
    <div className="app-shell">
      <header className="product-bar"><span className="product-mark">PFC</span><span>Configuration Tool</span></header>
      <main className="page-shell">
        <div className="page-heading"><div><span className="eyebrow">UB-04 institutional claim</span><h1>Customize Fields</h1></div><span className={`connection-status ${metadataError ? "offline" : ""}`}>{loading ? "Loading capabilities…" : metadataError ? "Capabilities unavailable" : "Capabilities loaded"}</span></div>

        <section className="context-card" aria-label="Configuration context">
          <dl className="context-grid">
            <div><dt>Payor</dt><dd>{UI_DEMO_DISPLAY_CONTEXT.payorName}</dd></div>
            <div><dt>Billing Form</dt><dd>{UI_DEMO_DISPLAY_CONTEXT.billingFormCode}</dd></div>
            <div><dt>Plan</dt><dd>{UI_DEMO_DISPLAY_CONTEXT.planName ?? "None"}</dd></div>
          </dl>
          {SUPPORT_DEVELOPER_MODE && <details className="technical-details context-technical"><summary>Technical details</summary><dl>
            <div><dt>Payor GUID</dt><dd><code>{UI_DEMO_LAUNCH_CONTEXT.payor_guid}</code></dd></div>
            <div><dt>Plan GUID</dt><dd><code>{UI_DEMO_LAUNCH_CONTEXT.plan_guid ?? "None"}</code></dd></div>
            <div><dt>PFC GUID</dt><dd><code>{UI_DEMO_LAUNCH_CONTEXT.pfc_guid}</code></dd></div>
          </dl></details>}
        </section>

        {metadataError && <div className="notice error metadata-error" role="alert"><div><strong>Configuration options could not be loaded</strong><p>{metadataError} Fields remain visible but cannot be edited.</p></div><button type="button" className="secondary-button" onClick={loadOptions}>Try Again</button></div>}

        <section className="claim-workspace" aria-label="UB-04 claim form fields">
          <div className="claim-toolbar"><div><h2>UB-04 claim fields</h2><p>Scroll the form and select an outlined field to configure its reporting behavior.</p></div><label className="search-field"><span>Find a field</span><input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Number or name" /></label></div>
          <div className="claim-form">
            {CLAIM_SECTION_LAYOUT.map((sectionDefinition) => {
              const sectionFields = visibleFields.filter((field) => field.section === sectionDefinition.name);
              if (sectionFields.length === 0) return null;
              return (
                <section className="claim-section" key={sectionDefinition.name}>
                  <header className="claim-section-header">
                    <h3>{sectionDefinition.name}</h3>
                    <span>Fields {sectionDefinition.range}</span>
                  </header>
                  <div className="claim-section-body">
                    {sectionDefinition.groups.map((group) => {
                      const groupFields = sectionFields.filter((field) => {
                        const fieldNumber = baseFieldNumber(field);
                        return fieldNumber >= group.from && fieldNumber <= group.through;
                      });
                      if (groupFields.length === 0) return null;
                      return (
                        <div className={`field-group field-group--${group.layout}`} key={group.id}>
                          {group.label && <h4 className="field-group-title">{group.label}</h4>}
                          <div className="field-grid">
                            {groupFields.map((field) => {
                              const available = catalogFieldIsAvailable(field, optionFields);
                              const canSpan = ["billing", "patient-details", "tail"].includes(group.layout);
                              const wide = canSpan && field.label.length > 35 ? " field-cell--wide" : "";
                              const reserved = /^(unlabeled|untitled)$/i.test(field.label) ? " field-cell--reserved" : "";
                              return (
                                <button
                                  type="button"
                                  className={`field-cell${wide}${reserved}${available ? " field-cell--configurable" : ""}`}
                                  key={field.id}
                                  disabled={!available}
                                  onClick={() => available && setSelectedField(field)}
                                  aria-label={`Field ${field.fieldNumber}, ${field.label}${available ? ", configurable" : ", not configurable yet"}`}
                                >
                                  <span className="field-cell-heading">
                                    <span className="field-number">{field.fieldNumber}</span>
                                    {available && <span className="edit-affordance" aria-hidden="true">Edit ›</span>}
                                  </span>
                                  <strong>{field.label}</strong>
                                  {available && field.capabilityKey && <small>{CAPABILITY_DESCRIPTION[field.capabilityKey].replace(" settings", "")}</small>}
                                </button>
                              );
                            })}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </section>
              );
            })}
            {visibleFields.length === 0 && <p className="empty-search">No fields match that search. Clear the search to view the complete catalog.</p>}
          </div>
        </section>
      </main>
      {selectedField && <FieldEditor field={selectedField} context={UI_DEMO_LAUNCH_CONTEXT} onClose={() => setSelectedField(null)} supportDeveloperMode={SUPPORT_DEVELOPER_MODE} />}
    </div>
  );
}
