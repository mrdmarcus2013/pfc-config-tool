import type {
  ConfigurationContextResponse,
  SupportPayorContext,
} from "../api/types";
import type { FrontendLaunchContext } from "../types/launch-context";

export const payorContextKey = (
  context: Pick<SupportPayorContext, "payor_guid" | "plan_guid">,
): string => JSON.stringify([context.payor_guid, context.plan_guid]);

export const payorContextLabel = (context: SupportPayorContext): string => {
  const payorLabel = context.payor_id
    ? `${context.payor_name} (${context.payor_id})`
    : context.payor_name;
  return context.plan_guid
    ? `${payorLabel} — Plan ${context.plan_guid}`
    : `${payorLabel} — No plan`;
};

export const launchContextFromResolvedSelection = (
  selection: SupportPayorContext,
  resolved: ConfigurationContextResponse,
  auditUser: string,
): FrontendLaunchContext => {
  if (selection.payor_guid !== resolved.payor_guid || selection.plan_guid !== resolved.plan_guid) {
    throw new Error("Resolved payor context did not match the selection.");
  }
  return {
    payor_guid: selection.payor_guid,
    plan_guid: selection.plan_guid,
    pfc_guid: resolved.pfc_guid,
    audit_user: auditUser,
  };
};
