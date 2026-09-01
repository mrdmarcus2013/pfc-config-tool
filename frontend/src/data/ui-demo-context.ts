import type { FrontendLaunchContext } from "../types/launch-context";

/** Local synthetic context only. Never replace these values with production data. */
export const UI_DEMO_LAUNCH_CONTEXT = {
  payor_guid: "10000000-0000-0000-0000-00000000D001",
  plan_guid: null,
  pfc_guid: "20000000-0000-0000-0000-00000000D001",
  audit_user: "90000000-0000-0000-0000-00000000D001",
} as const satisfies FrontendLaunchContext;

export const UI_DEMO_DISPLAY_CONTEXT = {
  payorName: "Synthetic UI Demo Payor",
  billingFormCode: "837I_5010",
  planName: null,
} as const;

