import { apiClient } from "../api/client.js";
import type { LineOfBusinessCurrentResponse } from "../api/types";
import { safeError } from "./workflow.js";

// Each displayed-context read owns its callbacks, including loading cleanup.
export function readCurrentLineOfBusiness(payorGuid: string, callbacks: {
  setCurrent: (current: LineOfBusinessCurrentResponse) => void;
  setLoading: (loading: boolean) => void;
  setError: (message: string | null) => void;
}): () => void {
  let currentRequest = true;
  callbacks.setLoading(true); callbacks.setError(null);
  void apiClient.lineOfBusinessCurrent({ payor_guid: payorGuid })
    .then(response => { if (currentRequest) callbacks.setCurrent(response); })
    .catch(caught => { if (currentRequest) callbacks.setError(safeError(caught).message); })
    .finally(() => { if (currentRequest) callbacks.setLoading(false); });
  return () => { currentRequest = false; };
}
