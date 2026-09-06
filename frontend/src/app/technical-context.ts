import type { ConfigurationContextResponse } from "../api/types";
import type { FrontendLaunchContext } from "../types/launch-context";

export interface TechnicalContextRow {
  label: string;
  value: string;
}

export const technicalContextRows = (
  launchContext: FrontendLaunchContext,
  resolvedContext: ConfigurationContextResponse | null,
  loading: boolean,
): TechnicalContextRow[] => {
  const unresolved = loading ? "Loading…" : "Unavailable";
  return [
    {
      label: "Payor GUID",
      value: resolvedContext?.payor_guid ?? launchContext.payor_guid,
    },
    {
      label: "Plan GUID",
      value: resolvedContext
        ? resolvedContext.plan_guid ?? "None"
        : launchContext.plan_guid ?? "None",
    },
    { label: "PFC GUID", value: resolvedContext?.pfc_guid ?? unresolved },
    {
      label: "Form Template GUID",
      value: resolvedContext ? resolvedContext.form_template_guid ?? "None" : unresolved,
    },
    {
      label: "Form Template Name",
      value: !resolvedContext ? unresolved : !resolvedContext.form_template_guid
        ? "None" : resolvedContext.form_template_name ?? "Unavailable",
    },
    {
      label: "User Form Template GUID",
      value: resolvedContext ? resolvedContext.user_form_template_guid ?? "None" : unresolved,
    },
    {
      label: "User Form Template Name",
      value: !resolvedContext ? unresolved : !resolvedContext.user_form_template_guid
        ? "None" : resolvedContext.user_form_template_name ?? "Unavailable",
    },
  ];
};
