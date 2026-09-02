import type {
  LineOfBusiness,
  LineOfBusinessApplyRequest,
  LineOfBusinessChangeResponse,
} from "../api/types";
import type { FrontendLaunchContext } from "../types/launch-context";

export const lineOfBusinessLabel = (value: LineOfBusiness): string =>
  value === "HOME_HEALTH" ? "Home Health" : "Hospice";

export const otherLineOfBusiness = (value: LineOfBusiness): LineOfBusiness =>
  value === "HOME_HEALTH" ? "HOSPICE" : "HOME_HEALTH";

export const fieldsUnlocked = (value: LineOfBusiness | null): boolean => value !== null;

export const lobApplyRequest = (
  context: FrontendLaunchContext,
  preview: LineOfBusinessChangeResponse,
): LineOfBusinessApplyRequest => ({
  payor_guid: context.payor_guid,
  requested_line_of_business: preview.requested_line_of_business,
  expected_state_hash: preview.preview_state_hash,
  audit_user: context.audit_user,
});

export const lobPreviewAfterError = (
  preview: LineOfBusinessChangeResponse | null,
  category: string,
): LineOfBusinessChangeResponse | null => category === "stale_preview" ? null : preview;
