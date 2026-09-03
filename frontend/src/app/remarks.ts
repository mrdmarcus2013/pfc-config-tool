import type {
  RemarksChangeRequest,
  RemarksCurrentResponse,
  RemarksMode,
} from "../api/types.js";
import type { FrontendLaunchContext } from "../types/launch-context";

/* Temporary configured limit; change this named frontend constant only. */
export const REMARKS_CUSTOM_REMARK_MAX_LENGTH = 100;

export interface RemarksIntent {
  mode: RemarksMode;
  customRemark: string;
}

export const normalizedCustomRemark = (value: string): string => value.trim();

export const remarksIntentIsValid = (intent: RemarksIntent): boolean => {
  if (intent.mode === "DEFAULT") return true;
  const value = normalizedCustomRemark(intent.customRemark);
  return value.length > 0 && value.length <= REMARKS_CUSTOM_REMARK_MAX_LENGTH;
};

export const remarksRequest = (
  context: FrontendLaunchContext,
  intent: RemarksIntent,
): RemarksChangeRequest => ({
  payor_guid: context.payor_guid,
  plan_guid: context.plan_guid,
  mode: intent.mode,
  custom_remark: intent.mode === "CUSTOM"
    ? normalizedCustomRemark(intent.customRemark)
    : null,
  audit_user: context.audit_user,
});

export const remarksIdentity = (
  context: FrontendLaunchContext,
  lineOfBusiness: string,
  intent: RemarksIntent,
): string => {
  const request = remarksRequest(context, intent);
  return [request.payor_guid, request.plan_guid ?? "", request.audit_user,
    lineOfBusiness, request.mode, request.custom_remark ?? ""].join("|");
};

export const remarksIntentMatchesCurrent = (
  current: RemarksCurrentResponse | null,
  intent: RemarksIntent,
): boolean => Boolean(current
  && current.mode === intent.mode
  && (current.mode === "DEFAULT"
    || current.custom_remark === normalizedCustomRemark(intent.customRemark)));

export const remarksIntentFromCurrent = (
  current: RemarksCurrentResponse,
): RemarksIntent => ({
  mode: current.mode,
  customRemark: current.custom_remark ?? "",
});
