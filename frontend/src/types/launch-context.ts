/**
 * Context supplied by the future host workflow.
 *
 * The identifiers follow the existing VARCHAR2-style contract and are not
 * assumed to be RFC UUIDs. They are context, not visible form inputs. Oracle
 * still resolves the winning PFC from payor_guid and plan_guid; pfc_guid must
 * not be treated as authority by the frontend.
 */
export interface FrontendLaunchContext {
  payor_guid: string;
  plan_guid: string | null;
  pfc_guid: string;
  audit_user: string;
}

