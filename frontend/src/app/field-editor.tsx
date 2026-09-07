import { useEffect, useRef, useState } from "react";
import { apiClient } from "../api/client.js";
import type { ConfigurationResponse, CurrentConfigurationResponse } from "../api/types";
import type {
  ProviderTaxonomySelection, PublicOptionCode, ServiceFacilityAddress, ServiceFacilityMode,
} from "../data/configuration-capabilities";
import type { ClaimFieldCatalogEntry } from "../types/claim-field";
import type { FrontendLaunchContext } from "../types/launch-context";
import { ConfigurationOwnerDetails, configurationSourceStatus } from "./configuration-owner-details.js";
import {
  currentConfigurationCache, currentConfigurationRequest, currentOptionDiffers,
  selectionsFromCurrent,
} from "./current-state.js";
import {
  currentPreview, previewAfterError, editorActionState, previewAllowsApply,
  previewIdentity, previewRequest, providerTaxonomyOption, safeError,
  serviceFacilityOption, SingleFlightGate,
} from "./workflow.js";
import { EditorFooter } from "./editor-footer.js";
import { ClaimFieldPanelHeader } from "./claim-field-panel-header.js";
import { ModalSurface } from "./modal-surface.js";
import { fieldEditorTitle } from "./presentation.js";
import { PreviewResult } from "./preview-result.js";
import { runEditorPreview, type PreviewRecord } from "./editor-preview.js";

const SERVICE_MODE_LABEL: Record<ServiceFacilityMode, string> = {
  always: "Always report service facility",
  conditional: "Only report service facility when care location is not HOME",
  never: "Never report service facility",
};

interface FieldEditorProps {
  field: ClaimFieldCatalogEntry;
  context: FrontendLaunchContext;
  onClose: () => void;
  supportDeveloperMode: boolean;
}

export function FieldEditor({ field, context, onClose, supportDeveloperMode }: FieldEditorProps) {
  const [serviceMode, setServiceMode] = useState<ServiceFacilityMode>("never");
  const [serviceAddress, setServiceAddress] = useState<ServiceFacilityAddress>("no");
  const [taxonomy, setTaxonomy] = useState<ProviderTaxonomySelection>("no");
  const [previewRecord, setPreviewRecord] = useState<PreviewRecord<ConfigurationResponse> | null>(null);
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

  const runPreview = () => runEditorPreview({
    canPreview: dirty, gate: requestGate.current, identity,
    request: () => apiClient.preview(previewRequest(context, optionCode)),
    setBusy, setError, setSuccess, setPreviewRecord,
  });

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
      <ModalSurface as="aside" className="field-editor" role="dialog" aria-modal="true" aria-labelledby="editor-title" onDismiss={onClose}>
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

        {confirmationOpen && <div className="confirmation-backdrop" role="presentation"><ModalSurface className="confirmation" role="alertdialog" aria-modal="true" aria-labelledby="confirmation-title" onDismiss={() => setConfirmationOpen(false)} focusOnOpen="first">
          <h3 id="confirmation-title">Apply configuration?</h3>
          <p><strong>Field {field.fieldNumber} — {field.label}</strong></p><p>{selectionSummary}</p>
          <div className="confirmation-actions"><button type="button" className="secondary-button" data-modal-initial-focus onClick={() => setConfirmationOpen(false)}>Cancel</button><button type="button" className="primary-button" disabled={busy !== null} onClick={runApply}>Apply</button></div>
        </ModalSurface></div>}
      </ModalSurface>
    </div>
  );
}
