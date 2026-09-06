import { clearCurrentConfigurations, subscribeCurrentConfigurations, loadConfigurationOverview,
  currentBoxSummary, valueCodesCurrentCache } from "./app/configuration-overview";
import { ConfigurationOwnerDetails, configurationSourceStatus } from "./app/configuration-owner-details";
import { useEffect, useMemo, useRef, useState } from "react";
import { apiClient } from "./api/client";
import type {
  ConfigurationResponse, CurrentConfigurationResponse, LineOfBusiness,
  ConfigurationContextResponse, LineOfBusinessChangeResponse,
  LineOfBusinessCurrentResponse, OptionField, SupportPayorContext,
  ValueCodeSelections, ValueCodesChangeResponse, ValueCodesCurrentResponse,
} from "./api/types";
import {
  currentConfigurationCache, currentConfigurationRequest, currentOptionDiffers,
  selectionsFromCurrent,
} from "./app/current-state";
import {
  catalogFieldIsAvailable, catalogFieldIsEditable, currentPreview,
  fieldEditorRoute, previewAfterError, selectCatalogFieldForEditor,
  editorActionState, previewAllowsApply, previewIdentity, previewRequest, providerTaxonomyOption,
  safeError, serviceFacilityOption, SingleFlightGate,
} from "./app/workflow";
import {
  fieldsUnlocked, lineOfBusinessLabel, lobApplyRequest,
  lobPreviewAfterError, otherLineOfBusiness,
} from "./app/line-of-business";
import { EditorFooter } from "./app/editor-footer";
import { ClaimFieldPanelHeader } from "./app/claim-field-panel-header";
import {
  fieldEditorTitle,
} from "./app/presentation";
import { SUPPORT_DEVELOPER_MODE } from "./app/environment";
import {
  launchContextFromResolvedSelection, payorContextKey,
} from "./app/payor-context";
import { ContextSelectors } from "./app/context-selectors";
import { technicalContextRows } from "./app/technical-context";
import {
  emptyValueCodeSelections, hospiceValueIsDisabled, setHomeHealthValue, setHospiceValue,
  valueCodeSelectionIdentity, valueCodeSelectionsEqual, valueCodesSummary,
} from "./app/value-codes";
import { PreviewResult } from "./app/preview-result";
import { RemarksEditor } from "./app/remarks-editor";
import { CLAIM_FIELD_CATALOG } from "./data/claim-field-catalog";
import type {
  ProviderTaxonomySelection, PublicOptionCode, ServiceFacilityAddress, ServiceFacilityMode,
} from "./data/configuration-capabilities";
import { UI_DEMO_DISPLAY_CONTEXT, UI_DEMO_LAUNCH_CONTEXT } from "./data/ui-demo-context";
import type { ClaimFieldCatalogEntry, ClaimFieldSection } from "./types/claim-field";
import type { FrontendLaunchContext } from "./types/launch-context";

const INITIAL_PAYOR_CONTEXT: SupportPayorContext = {
  payor_guid: UI_DEMO_LAUNCH_CONTEXT.payor_guid,
  payor_name: UI_DEMO_DISPLAY_CONTEXT.payorName,
  payor_id: UI_DEMO_DISPLAY_CONTEXT.payorId,
  plan_guid: UI_DEMO_LAUNCH_CONTEXT.plan_guid,
};

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

interface ValueCodesEditorProps {
  field: ClaimFieldCatalogEntry;
  context: FrontendLaunchContext;
  lineOfBusiness: LineOfBusiness;
  onClose: () => void;
  supportDeveloperMode: boolean;
}

function ValueCodesEditor({ field, context, lineOfBusiness, onClose, supportDeveloperMode }: ValueCodesEditorProps) {
  const [current, setCurrent] = useState<ValueCodesCurrentResponse | null>(null);
  const [selected, setSelected] = useState<ValueCodeSelections>(emptyValueCodeSelections);
  const [previewRecord, setPreviewRecord] = useState<{ identity: string; response: ValueCodesChangeResponse } | null>(null);
  const [busy, setBusy] = useState<"preview" | "apply" | null>(null);
  const [error, setError] = useState<{ category: string; message: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [confirmationOpen, setConfirmationOpen] = useState(false);
  const [success, setSuccess] = useState(false);
  const gate = useRef(new SingleFlightGate());
  const request = { payor_guid: context.payor_guid, plan_guid: context.plan_guid };
  const identity = valueCodeSelectionIdentity(context, lineOfBusiness, selected);
  const preview = previewRecord?.identity === identity ? previewRecord.response : null;
  const dirty = current !== null && !valueCodeSelectionsEqual(current.selections, selected);
  const actionState = editorActionState({ dirty, preview, busy, applyCompleted: success });

  const initialize = (response: ValueCodesCurrentResponse) => {
    setCurrent(response); setSelected(response.selections); setPreviewRecord(null);
    setConfirmationOpen(false);
  };
  const loadCurrent = async (force = false) => {
    setLoading(true); setError(null);
    try { const response = await valueCodesCurrentCache.load({ ...request, field_number: "39-41" }, () => apiClient.valueCodesCurrent(request), force); initialize(response); return response; }
    catch (caught) { setCurrent(null); setError(safeError(caught)); return null; }
    finally { setLoading(false); }
  };
  useEffect(() => { void loadCurrent(); }, [context.payor_guid, context.plan_guid, lineOfBusiness]);

  const update = (next: ValueCodeSelections) => {
    setSelected(next); setPreviewRecord(null); setError(null); setSuccess(false); setConfirmationOpen(false);
  };
  const runPreview = async () => {
    if (!dirty || !gate.current.tryEnter()) return;
    setBusy("preview"); setError(null); setSuccess(false);
    try {
      const response = await apiClient.valueCodesPreview({ ...request, selections: selected, audit_user: context.audit_user });
      setPreviewRecord({ identity, response });
    } catch (caught) { setPreviewRecord(null); setError(safeError(caught)); }
    finally { setBusy(null); gate.current.exit(); }
  };
  const runApply = async () => {
    if (!dirty || !previewAllowsApply(preview) || !gate.current.tryEnter()) return;
    setBusy("apply"); setConfirmationOpen(false); setError(null);
    try {
      await apiClient.valueCodesApply({ ...request, selections: selected,
        audit_user: context.audit_user, expected_state_hash: preview!.state_hash });
      setPreviewRecord(null); setSuccess(false);
      const refreshed = await loadCurrent(true);
      if (refreshed && valueCodeSelectionsEqual(refreshed.selections, selected)) setSuccess(true);
      else if (refreshed) setError({ category: "confirmation_failed", message: "The applied Value Codes configuration could not be confirmed." });
    } catch (caught) {
      const safe = safeError(caught); setError(safe);
      if (safe.category === "stale_preview") setPreviewRecord(null);
    } finally { setBusy(null); gate.current.exit(); }
  };
  const summary = valueCodesSummary(lineOfBusiness, selected);
  return <div className="drawer-backdrop" role="presentation">
    <aside className="field-editor" role="dialog" aria-modal="true" aria-labelledby="editor-title">
      <ClaimFieldPanelHeader title="Value Codes" onClose={onClose} />
      <div className="editor-body"><section className="editor-section"><h3>Value Codes</h3>
        {loading && <p className="current-loading" role="status">Loading current configuration…</p>}
        {current && <><div className="configuration-stage current-configuration">
          <h4 className="configuration-stage-title">Current configuration</h4>
          <p><strong>{current.display_summary}</strong></p>
          {current.is_default && <p className="helper">Uses the standard configuration inherited for this payor.</p>}
          {supportDeveloperMode && <details className="technical-details"><summary>Technical details</summary><dl>
            <div><dt>Canonical status</dt><dd>{configurationSourceStatus(current.configuration_owners)}</dd></div>
            <div><dt>PFC GUID</dt><dd><code>{current.pfc_guid}</code></dd></div>
                        <ConfigurationOwnerDetails owners={current.configuration_owners} />
            {Object.entries(current.debug).map(([key, value]) => <div key={key}><dt>{key}</dt><dd><code>{String(value ?? "")}</code></dd></div>)}
          </dl></details>}
        </div><div className="configuration-stage proposed-configuration">
          <h4 className="configuration-stage-title">Proposed configuration</h4>
          {lineOfBusiness === "HOME_HEALTH" ? <fieldset><legend>Value Code capabilities</legend>
            <label className="choice"><input type="checkbox" checked={selected.cbsa} onChange={(event) => update(setHomeHealthValue(selected, "cbsa", event.target.checked))}/><span>Add CBSA</span></label>
            <label className="choice"><input type="checkbox" checked={selected.fips} onChange={(event) => update(setHomeHealthValue(selected, "fips", event.target.checked))}/><span>Add FIPS</span></label>
          </fieldset> : <fieldset><legend>Value Code capabilities</legend>
            <label className="choice"><input type="checkbox" checked={selected.care_location_value_code} disabled={hospiceValueIsDisabled(selected, "care_location_value_code")} onChange={(event) => update(setHospiceValue(selected, "care_location_value_code", event.target.checked))}/><span>Add care-location value code 61/G8</span></label>
            <label className="choice"><input type="checkbox" checked={selected.patient_entered_value_code} disabled={hospiceValueIsDisabled(selected, "patient_entered_value_code")} onChange={(event) => update(setHospiceValue(selected, "patient_entered_value_code", event.target.checked))}/><span>Add patient-entered value code and amount</span></label>
            <label className="choice"><input type="checkbox" checked={selected.covered_days_value_code} onChange={(event) => update(setHospiceValue(selected, "covered_days_value_code", event.target.checked))}/><span>Add value code 80 with days covered</span></label>
          </fieldset>}
          <p><strong>{summary}</strong></p><p className={dirty ? "dirty-indicator" : "unchanged-indicator"}>{dirty ? "Proposed configuration differs from the current configuration." : "Matches current configuration."}</p>
        </div></>}
        {error && <div className={`notice error ${error.category === "stale_preview" ? "stale" : ""}`} role="alert"><strong>Unable to complete request</strong><p>{error.message}</p></div>}
        {success && <div className="notice success" role="status"><strong>Configuration applied</strong><p>The requested Value Codes configuration was applied and refreshed.</p></div>}
        {preview && <div className="configuration-stage preview-stage"><h4 className="configuration-stage-title">Preview</h4><p>{preview.summary}</p>
          {supportDeveloperMode && <details className="technical-details"><summary>Technical details</summary><dl><div><dt>State hash</dt><dd><code>{preview.state_hash}</code></dd></div></dl></details>}
        </div>}
      </section></div>
      <EditorFooter actionState={actionState} previewDisabled={busy !== null || loading || current === null || !dirty}
        previewLabel={busy === "preview" ? "Previewing…" : "Preview"} onDismiss={onClose} onPreview={runPreview} onApply={() => setConfirmationOpen(true)}/>
      {confirmationOpen && <div className="confirmation-backdrop" role="presentation"><div className="confirmation" role="alertdialog" aria-modal="true"><h3>Apply configuration?</h3><p><strong>{field.fieldNumber} — Value Codes</strong></p><p>{summary}</p><div className="confirmation-actions"><button type="button" className="secondary-button" onClick={() => setConfirmationOpen(false)}>Cancel</button><button type="button" className="primary-button" onClick={runApply}>Apply</button></div></div></div>}
    </aside></div>;
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
        <ClaimFieldPanelHeader title={fieldEditorTitle(field)} onClose={onClose} />

        <div className="editor-body">
          <section className="editor-section">
            <h3>{field.capabilityKey === "service-facility" ? "Service Facility Reporting" : "Provider Taxonomy"}</h3>
            {currentLoading && <p className="current-loading" role="status">Loading current configuration…</p>}
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
                        <ConfigurationOwnerDetails owners={currentConfig.configuration_owners} />
                        <div><dt>Canonical status</dt><dd>{configurationSourceStatus(currentConfig.configuration_owners)}</dd></div>
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

interface LineOfBusinessControlProps {
  context: FrontendLaunchContext;
  current: LineOfBusinessCurrentResponse | null;
  loading: boolean;
  disabled: boolean;
  onChanged: (lineOfBusiness: LineOfBusiness, message: string) => void;
  onChangeStarted: () => void;
}

function LineOfBusinessControl({ context, current, loading, disabled, onChanged, onChangeStarted }: LineOfBusinessControlProps) {
  const saved = current?.line_of_business ?? null;
  const [selection, setSelection] = useState<LineOfBusiness | null>(null);
  const [stage, setStage] = useState<"warning" | "confirm" | null>(null);
  const [preview, setPreview] = useState<LineOfBusinessChangeResponse | null>(null);
  const [busy, setBusy] = useState<"save" | "preview" | "apply" | null>(null);
  const [error, setError] = useState<{ category: string; message: string } | null>(null);
  const requestGate = useRef(new SingleFlightGate());

  useEffect(() => { if (saved) setSelection(saved); }, [saved]);

  const saveInitial = async () => {
    if (!selection || saved || !requestGate.current.tryEnter()) return;
    setBusy("save"); setError(null);
    try {
      const response = await apiClient.lineOfBusinessSave({
        payor_guid: context.payor_guid,
        line_of_business: selection,
        audit_user: context.audit_user,
      });
      clearCurrentConfigurations();
      onChanged(response.line_of_business, `${lineOfBusinessLabel(response.line_of_business)} was saved.`);
    } catch (caught) { setError(safeError(caught)); }
    finally { setBusy(null); requestGate.current.exit(); }
  };

  const beginChange = () => {
    if (!saved) return;
    onChangeStarted();
    setSelection(otherLineOfBusiness(saved));
    setPreview(null); setError(null); setStage("warning");
  };

  const runChangePreview = async () => {
    if (!saved || !selection || selection === saved || !requestGate.current.tryEnter()) return;
    setBusy("preview"); setError(null);
    try {
      const response = await apiClient.lineOfBusinessPreviewChange({
        payor_guid: context.payor_guid,
        requested_line_of_business: selection,
      });
      setPreview(response);
      setStage(response.status === "NO_CHANGE" ? null : "confirm");
    } catch (caught) { setError(safeError(caught)); }
    finally { setBusy(null); requestGate.current.exit(); }
  };

  const applyChange = async () => {
    if (!preview || preview.status !== "CHANGES_REQUIRED" || !requestGate.current.tryEnter()) return;
    setBusy("apply"); setError(null);
    try {
      const response = await apiClient.lineOfBusinessApplyChange(
        lobApplyRequest(context, preview),
      );
      clearCurrentConfigurations();
      setPreview(null); setStage(null);
      onChanged(response.requested_line_of_business,
        `Line of Business changed to ${lineOfBusinessLabel(response.requested_line_of_business)}. Managed claim-field customizations were reset for all plans.`);
    } catch (caught) {
      const safe = safeError(caught);
      setPreview((value) => lobPreviewAfterError(value, safe.category));
      setError(safe);
      if (safe.category === "stale_preview") setStage("warning");
    } finally { setBusy(null); requestGate.current.exit(); }
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

export function App() {
  const [, setCurrentRevision] = useState(0);
  useEffect(() => subscribeCurrentConfigurations(() => setCurrentRevision((value) => value + 1)), []);
  const [optionFields, setOptionFields] = useState<OptionField[]>([]);
  const [metadataError, setMetadataError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [selectedField, setSelectedField] = useState<ClaimFieldCatalogEntry | null>(null);
  const [lobCurrent, setLobCurrent] = useState<LineOfBusinessCurrentResponse | null>(null);
  const [lobLoading, setLobLoading] = useState(true);
  const [lobError, setLobError] = useState<string | null>(null);
  const [lobSuccess, setLobSuccess] = useState<string | null>(null);
  const [configurationContext, setConfigurationContext] =
    useState<ConfigurationContextResponse | null>(null);
  const [contextLoading, setContextLoading] = useState(SUPPORT_DEVELOPER_MODE);
  const [contextError, setContextError] = useState<string | null>(null);
  const [activeContext, setActiveContext] =
    useState<FrontendLaunchContext>(UI_DEMO_LAUNCH_CONTEXT);
  const [activePayorContext, setActivePayorContext] =
    useState<SupportPayorContext>(INITIAL_PAYOR_CONTEXT);
  const [supportPayorContexts, setSupportPayorContexts] =
    useState<SupportPayorContext[]>([]);
  const [payorCatalogLoading, setPayorCatalogLoading] =
    useState(SUPPORT_DEVELOPER_MODE);
  const [payorCatalogError, setPayorCatalogError] = useState<string | null>(null);
  const [contextSwitching, setContextSwitching] = useState(false);
  const [payorSwitchError, setPayorSwitchError] = useState<string | null>(null);
  const contextRequestSequence = useRef(0);
  const activeContextKey = payorContextKey(activePayorContext);

  const loadOptions = async () => {
    setLoading(true); setMetadataError(null);
    try { setOptionFields((await apiClient.options()).fields); }
    catch (caught) { setOptionFields([]); setMetadataError(safeError(caught).message); }
    finally { setLoading(false); }
  };
  useEffect(() => { void loadOptions(); }, []);
  useEffect(() => {
    let currentRequest = true;
    setLobLoading(true); setLobError(null);
    void apiClient.lineOfBusinessCurrent({ payor_guid: activeContext.payor_guid })
      .then((response) => { if (currentRequest) setLobCurrent(response); })
      .catch((caught) => { if (currentRequest) setLobError(safeError(caught).message); })
      .finally(() => { if (currentRequest) setLobLoading(false); });
    return () => { currentRequest = false; };
  }, [activeContextKey]);
  useEffect(() => {
    let mounted = true;
    setPayorCatalogLoading(true); setPayorCatalogError(null);
    void apiClient.supportPayorContexts()
      .then((response) => {
        if (!mounted) return;
        setSupportPayorContexts(response.contexts);
        const current = response.contexts.find(
          (context) => payorContextKey(context) === activeContextKey,
        );
        if (current) setActivePayorContext(current);
      })
      .catch((caught) => {
        if (mounted) setPayorCatalogError(safeError(caught).message);
      })
      .finally(() => { if (mounted) setPayorCatalogLoading(false); });

    const requestNumber = ++contextRequestSequence.current;
    setContextLoading(true); setContextError(null);
    void apiClient.configurationContext({
      payor_guid: activeContext.payor_guid,
      plan_guid: activeContext.plan_guid,
    })
      .then((response) => {
        if (mounted && requestNumber === contextRequestSequence.current) {
          setConfigurationContext(response);
          setActiveContext(launchContextFromResolvedSelection(
            INITIAL_PAYOR_CONTEXT, response, activeContext.audit_user,
          ));
        }
      })
      .catch((caught) => {
        if (mounted && requestNumber === contextRequestSequence.current) {
          setContextError(safeError(caught).message);
        }
      })
      .finally(() => {
        if (mounted && requestNumber === contextRequestSequence.current) {
          setContextLoading(false);
        }
      });
    return () => { mounted = false; };
  }, []);

  const selectPayorContext = async (selectionKey: string) => {
    const selection = supportPayorContexts.find(
      (context) => payorContextKey(context) === selectionKey,
    );
    if (!selection || (selectionKey === activeContextKey && configurationContext)) return;
    if (selectedField && !window.confirm("Discard the open editor and switch configuration?")) return;
    const requestNumber = ++contextRequestSequence.current;
    setContextSwitching(true); setContextLoading(true);
    setContextError(null); setPayorSwitchError(null); setSelectedField(null);
    try {
      const resolved = await apiClient.configurationContext({
        payor_guid: selection.payor_guid,
        plan_guid: selection.plan_guid,
      });
      if (requestNumber !== contextRequestSequence.current) return;
      const nextContext = launchContextFromResolvedSelection(
        selection, resolved, activeContext.audit_user,
      );
      clearCurrentConfigurations();
      setLobCurrent(null); setLobLoading(true); setLobError(null); setLobSuccess(null);
      setActivePayorContext(selection);
      setActiveContext(nextContext);
      setConfigurationContext(resolved);
      setContextError(null);
    } catch (caught) {
      if (requestNumber === contextRequestSequence.current) {
        setPayorSwitchError(safeError(caught).message);
      }
    } finally {
      if (requestNumber === contextRequestSequence.current) {
        setContextSwitching(false); setContextLoading(false);
      }
    }
  };

  const lob = lobCurrent?.line_of_business ?? null;
  const unlocked = fieldsUnlocked(lob);
  useEffect(() => {
    if (contextSwitching || lobLoading || lobError || !lob) return;
    void loadConfigurationOverview({ payor_guid: activeContext.payor_guid, plan_guid: activeContext.plan_guid });
  }, [activeContextKey, lob, lobLoading, lobError, contextSwitching]);

  const boxSummary = (capability: NonNullable<ClaimFieldCatalogEntry["capabilityKey"]>) => {
    if (contextSwitching || lobLoading) return "Loading?";
    if (lobError) return "Unable to determine";
    if (!lob) return "Set Line of Business";
    return currentBoxSummary(capability, activeContext);
  };


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
          <ContextSelectors contexts={supportPayorContexts} active={activePayorContext}
            disabled={payorCatalogLoading || contextSwitching}
            billingForm={configurationContext?.billing_form_code ?? "Unavailable"}
            onSelect={key => { void selectPayorContext(key); }} />
          {(payorCatalogError || payorSwitchError) && <p role="alert">{payorCatalogError ?? payorSwitchError}</p>}
          <p className="context-inheritance">{activeContext.plan_guid
            ? "Editing this plan. Default inherits payor settings."
            : "Editing payor settings. Changes also affect plans that inherit these settings."}</p>
          {SUPPORT_DEVELOPER_MODE && <details className="technical-details context-technical"><summary>Technical details</summary>
            {contextError && <p role="alert">Template context unavailable. {contextError}</p>}
            <dl>{technicalContextRows(activeContext, configurationContext, contextLoading)
              .map((row) => <div key={row.label}><dt>{row.label}</dt><dd><code>{row.value}</code></dd></div>)}</dl>
          </details>}
        </section>

        <LineOfBusinessControl key={`${activeContextKey}|${contextSwitching}`}
          context={activeContext} current={lobCurrent} loading={lobLoading}
          disabled={contextSwitching}
          onChangeStarted={() => { setSelectedField(null); setLobSuccess(null); }}
          onChanged={(lineOfBusiness, message) => {
            clearCurrentConfigurations();
            setSelectedField(null); setLobSuccess(message); setLobError(null);
            setLobCurrent({ status: "DEFINED", line_of_business: lineOfBusiness });
          }} />

        {lobError && <div className="notice error" role="alert"><strong>Line of Business could not be loaded</strong><p>{lobError} Claim fields cannot be edited.</p></div>}
        {lobSuccess && <div className="notice success" role="status"><strong>Line of Business updated</strong><p>{lobSuccess}</p></div>}
        {!lobLoading && !lobError && !unlocked && <div className="notice lob-required" role="status"><strong>Line of Business required</strong><p>Select and save a Line of Business before configuring claim fields.</p></div>}

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
                              const available = !loading && !metadataError
                                && catalogFieldIsAvailable(field, optionFields);
                              const editable = !contextSwitching && available
                                && catalogFieldIsEditable(field, optionFields, lob);
                              const canSpan = ["billing", "patient-details", "tail"].includes(group.layout);
                              const wide = canSpan && field.label.length > 35 ? " field-cell--wide" : "";
                              const reserved = /^(unlabeled|untitled)$/i.test(field.label) ? " field-cell--reserved" : "";
                              return (
                                <button
                                  type="button"
                                  className={`field-cell${wide}${reserved}${available ? " field-cell--configurable" : ""}${available && !unlocked ? " field-cell--locked" : ""}`}
                                  key={field.id}
                                  disabled={!editable}
                                  onClick={() => setSelectedField(
                                    selectCatalogFieldForEditor(field, optionFields, lob),
                                  )}
                                  aria-label={`Field ${field.fieldNumber}, ${field.label}${available && field.capabilityKey ? `, Current configuration: ${boxSummary(field.capabilityKey)}` : ""}${editable ? ", configurable" : available ? ", requires Line of Business" : ", not configurable yet"}`}
                                >
                                  <span className="field-cell-heading">
                                    <span className="field-number">{field.fieldNumber}</span>
                                    {available && <span className="edit-affordance" aria-hidden="true">{unlocked ? "Edit ›" : "Locked"}</span>}
                                  </span>
                                  <strong>{field.label}</strong>
                                  {available && field.capabilityKey && <span className="field-current-summary" aria-live="polite">
                                    <span className="field-current-label">Current configuration</span>
                                    <span>{boxSummary(field.capabilityKey)}</span>
                                  </span>}
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
      {selectedField && lob && (fieldEditorRoute(selectedField) === "value-codes"
        ? <ValueCodesEditor field={selectedField} context={activeContext} lineOfBusiness={lob} onClose={() => setSelectedField(null)} supportDeveloperMode={SUPPORT_DEVELOPER_MODE} />
        : fieldEditorRoute(selectedField) === "remarks"
          ? <RemarksEditor field={selectedField} context={activeContext} lineOfBusiness={lob} onClose={() => setSelectedField(null)} supportDeveloperMode={SUPPORT_DEVELOPER_MODE} />
          : <FieldEditor field={selectedField} context={activeContext} onClose={() => setSelectedField(null)} supportDeveloperMode={SUPPORT_DEVELOPER_MODE} />)}
    </div>
  );
}
