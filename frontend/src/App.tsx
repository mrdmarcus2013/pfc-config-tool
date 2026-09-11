import {
  clearCurrentConfigurations, subscribeCurrentConfigurations, loadConfigurationOverview,
  currentBoxSummary,
} from "./app/configuration-overview";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { apiClient } from "./api/client";
import type {
  ConfigurationContextResponse, LineOfBusinessCurrentResponse, OptionField, SupportPayorContext,
} from "./api/types";
import {
  catalogFieldIsAvailable, catalogFieldIsEditable, fieldEditorRoute,
  selectCatalogFieldForEditor, safeError,
} from "./app/workflow";
import { fieldsUnlocked } from "./app/line-of-business";
import { readCurrentLineOfBusiness } from "./app/line-of-business-current";
import { SUPPORT_DEVELOPER_MODE } from "./app/environment";
import { launchContextFromResolvedSelection, payorContextKey } from "./app/payor-context";
import { PayorCopyPanel } from "./app/payor-copy-panel";
import { ContextSelectors } from "./app/context-selectors";
import { technicalContextRows } from "./app/technical-context";
import { FieldEditor } from "./app/field-editor";
import { ValueCodesEditor } from "./app/value-codes-editor";
import { LineOfBusinessControl } from "./app/line-of-business-control";
import { CLAIM_SECTION_LAYOUT, baseFieldNumber } from "./app/claim-section-layout";
import { RemarksEditor } from "./app/remarks-editor";
import { CLAIM_FIELD_CATALOG } from "./data/claim-field-catalog";
import { UI_DEMO_DISPLAY_CONTEXT, UI_DEMO_LAUNCH_CONTEXT } from "./data/ui-demo-context";
import type { ClaimFieldCatalogEntry } from "./types/claim-field";
import type { FrontendLaunchContext } from "./types/launch-context";

const INITIAL_PAYOR_CONTEXT: SupportPayorContext = {
  payor_guid: UI_DEMO_LAUNCH_CONTEXT.payor_guid,
  payor_name: UI_DEMO_DISPLAY_CONTEXT.payorName,
  payor_id: UI_DEMO_DISPLAY_CONTEXT.payorId,
  plan_guid: UI_DEMO_LAUNCH_CONTEXT.plan_guid,
};

export function App() {
  const [, setCurrentRevision] = useState(0);
  useEffect(() => subscribeCurrentConfigurations(() => setCurrentRevision((value) => value + 1)), []);
  const [copySource, setCopySource] = useState<{ context: FrontendLaunchContext; label: string } | null>(null);
  const copyLauncher = useRef<HTMLButtonElement>(null);
  const [optionFields, setOptionFields] = useState<OptionField[]>([]);
  const [metadataError, setMetadataError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [selectedField, setSelectedField] = useState<ClaimFieldCatalogEntry | null>(null);
  const [lobCurrent, setLobCurrent] = useState<LineOfBusinessCurrentResponse | null>(null);
  const [lobLoading, setLobLoading] = useState(true);
  const [lobError, setLobError] = useState<string | null>(null);
  const [lobSuccess, setLobSuccess] = useState<string | null>(null);
  const [lobRefreshRevision, setLobRefreshRevision] = useState(0);
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
  const appMounted = useRef(false);
  useLayoutEffect(() => {
    appMounted.current = true;
    return () => { appMounted.current = false; };
  }, []);
  // A callback from an earlier visit stays stale even when returning to a payor.
  const lobContextRequest = contextRequestSequence.current;
  const activeContextKey = payorContextKey(activePayorContext);

  const loadOptions = async () => {
    setLoading(true); setMetadataError(null);
    try { setOptionFields((await apiClient.options()).fields); }
    catch (caught) { setOptionFields([]); setMetadataError(safeError(caught).message); }
    finally { setLoading(false); }
  };
  useEffect(() => { void loadOptions(); }, []);
  useEffect(() => {
    if (contextSwitching) return;
    return readCurrentLineOfBusiness(activeContext.payor_guid, {
      setCurrent: setLobCurrent, setLoading: setLobLoading, setError: setLobError,
    });
  }, [activeContextKey, contextSwitching, lobRefreshRevision]);
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
      {copySource && <PayorCopyPanel source={copySource.context} sourceLabel={copySource.label}
        supportDeveloperMode={SUPPORT_DEVELOPER_MODE}
        returnFocusElement={copyLauncher.current}
        onClose={() => setCopySource(null)}
        onApplied={destination => { clearCurrentConfigurations(); void selectPayorContext(payorContextKey({ payor_guid: destination, plan_guid: null })); }} />}
      <main className="page-shell">
        <div className="page-heading"><div><span className="eyebrow">UB-04 institutional claim</span><h1 tabIndex={-1} data-modal-return-target>Customize Fields</h1></div><span className={`connection-status ${metadataError ? "offline" : ""}`}>{loading ? "Loading capabilities…" : metadataError ? "Capabilities unavailable" : "Capabilities loaded"}</span></div>

        <section className="context-card" aria-label="Configuration context">
          <ContextSelectors contexts={supportPayorContexts} active={activePayorContext}
            disabled={payorCatalogLoading || contextSwitching || copySource !== null}
            billingForm={configurationContext?.billing_form_code ?? "Unavailable"}
            onSelect={key => { void selectPayorContext(key); }} />
          {(payorCatalogError || payorSwitchError) && <p role="alert">{payorCatalogError ?? payorSwitchError}</p>}
          <button ref={copyLauncher} className="secondary-button copy-launch" disabled={contextSwitching || contextLoading || payorCatalogLoading || !configurationContext || !lob || copySource !== null}
            onClick={() => { setSelectedField(null); setCopySource({ context: { ...activeContext },
              label: activePayorContext.payor_name + " ? " + (activeContext.plan_guid ? activePayorContext.plan_name ?? "Selected plan" : "All Plans") }); }}>
            COPY PAYOR SETTINGS
          </button>
          <p className="context-inheritance">{activeContext.plan_guid
            ? "Editing only the selected plan."
            : "Editing payor settings. Changes also apply to plans without their own setting."}</p>
          {SUPPORT_DEVELOPER_MODE && <details className="technical-details context-technical"><summary>Technical details</summary>
            <p>{activeContext.plan_guid
              ? "Default inherits payor settings."
              : "Plans inherit payor settings unless an applicable plan override takes precedence."}</p>
            {contextError && <p role="alert">Template context unavailable. {contextError}</p>}
            <dl>{technicalContextRows(activeContext, configurationContext, contextLoading)
              .map((row) => <div key={row.label}><dt>{row.label}</dt><dd><code>{row.value}</code></dd></div>)}</dl>
          </details>}
        </section>

        <LineOfBusinessControl key={`${activeContextKey}|${contextSwitching}`}
          context={activeContext} current={lobCurrent} loading={lobLoading}
          disabled={contextSwitching}
          onSaved={() => { if (appMounted.current) setLobRefreshRevision(value => value + 1); }}
          onChangeStarted={() => { setSelectedField(null); setLobSuccess(null); }}
          onChanged={(lineOfBusiness, message) => {
            if (!appMounted.current || lobContextRequest !== contextRequestSequence.current) return;
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
