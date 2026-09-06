import { apiClient, ApiClientError } from "../api/client.js";
import type {
  ConfigurationContextRequest, ConfigurationOverviewResponse, CurrentConfigurationResponse,
  RemarksCurrentResponse, ValueCodesCurrentResponse,
} from "../api/types";
import type { ClaimFieldCapabilityKey } from "../types/claim-field";
import { CurrentConfigurationCache, currentConfigurationCache } from "./current-state.js";
import { valueCodesSummary } from "./value-codes.js";

export const valueCodesCurrentCache = new CurrentConfigurationCache<ValueCodesCurrentResponse>();
export const remarksCurrentCache = new CurrentConfigurationCache<RemarksCurrentResponse>();

export function clearCurrentConfigurations(): void {
  currentConfigurationCache.clear(); valueCodesCurrentCache.clear(); remarksCurrentCache.clear();
}

export function subscribeCurrentConfigurations(listener: () => void): () => void {
  const unsubscribes = [currentConfigurationCache, valueCodesCurrentCache, remarksCurrentCache]
    .map((cache) => cache.subscribe(listener));
  return () => unsubscribes.forEach((unsubscribe) => unsubscribe());
}

export async function loadConfigurationOverview(context: ConfigurationContextRequest): Promise<void> {
  let overview: Promise<ConfigurationOverviewResponse> | undefined;
  async function read<K extends keyof ConfigurationOverviewResponse["fields"]>(field: K) {
    overview ??= apiClient.overview(context);
    const item = (await overview).fields[field];
    if (item.status !== "RESOLVED" || !item.current) {
      throw new ApiClientError(item.error?.category ?? "current_state_unavailable",
        item.error?.message ?? "The current configuration could not be determined.", 409);
    }
    return item.current;
  }
  await Promise.allSettled([
    currentConfigurationCache.load({ ...context, field_number: "77" }, () => read("77")),
    currentConfigurationCache.load({ ...context, field_number: "81" }, () => read("81")),
    valueCodesCurrentCache.load({ ...context, field_number: "39-41" }, () => read("39-41")),
    remarksCurrentCache.load({ ...context, field_number: "80" }, () => read("80")),
  ]);
}

export function genericCurrentSummary(current: CurrentConfigurationResponse): string {
  if (current.capability === "provider-taxonomy") return `Billing Provider Taxonomy ${current.display.enabled ? "On" : "Off"}`;
  if (current.display.mode === "NEVER") return "Off";
  const mode = current.display.mode === "ALWAYS" ? "Always" : "When not HOME";
  return `${mode} · ${current.display.report_address === "Y" ? "Address included" : "No address"}`;
}

export function valueCodesCurrentSummary(current: ValueCodesCurrentResponse): string {
  const summary = (current.is_default ? current.display_summary
    : valueCodesSummary(current.line_of_business, current.selections)).replace(/\s*\(inherited\)$/i, "");
  const compact: Record<string, string> = {
    "CBSA and FIPS": "CBSA + FIPS",
    "Care-location value code 61/G8": "Care location 61/G8",
    "Care-location value code 61/G8 and value code 80 with days covered": "Care location 61/G8 + VC80/days",
    "Patient-entered value code and amount": "Patient-entered value codes",
    "Patient-entered value code and amount and value code 80 with days covered": "Patient-entered + VC80/days",
    "Value code 80 with days covered": "VC80/days",
    "Default": "Inherited settings",
  };
  return compact[summary] ?? summary;
}

export function currentBoxSummary(capability: ClaimFieldCapabilityKey, context: ConfigurationContextRequest): string {
  if (capability === "value-codes") {
    const entry = valueCodesCurrentCache.peek({ ...context, field_number: "39-41" });
    return entry.status === "ready" ? valueCodesCurrentSummary(entry.current)
      : entry.status === "error" ? "Unable to determine" : "Loading…";
  }
  if (capability === "remarks") {
    const entry = remarksCurrentCache.peek({ ...context, field_number: "80" });
    if (entry.status !== "ready") return entry.status === "error" ? "Unable to determine" : "Loading…";
    if (entry.current.mode !== "CUSTOM") return "Standard Remarks";
    const remark = Array.from(entry.current.custom_remark ?? "");
    const excerpt = remark.slice(0, 100).join("") + (remark.length > 100 ? "…" : "");
    return excerpt ? `Custom Remarks: ${excerpt}` : "Custom Remarks";
  }
  const entry = currentConfigurationCache.peek({ ...context,
    field_number: capability === "service-facility" ? "77" : "81" });
  return entry.status === "ready" ? genericCurrentSummary(entry.current)
    : entry.status === "error" ? "Unable to determine" : "Loading…";
}
