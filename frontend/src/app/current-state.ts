import type { CurrentConfigurationRequest, CurrentConfigurationResponse } from "../api/types";
import type {
  ProviderTaxonomySelection,
  PublicOptionCode,
  ServiceFacilityAddress,
  ServiceFacilityMode,
} from "../data/configuration-capabilities";
import type { FrontendLaunchContext } from "../types/launch-context";

export interface CurrentSelections {
  serviceMode: ServiceFacilityMode;
  serviceAddress: ServiceFacilityAddress;
  taxonomy: ProviderTaxonomySelection;
}

export const currentConfigurationRequest = (
  context: FrontendLaunchContext,
  fieldNumber: "77" | "81",
): CurrentConfigurationRequest => ({
  payor_guid: context.payor_guid,
  plan_guid: context.plan_guid,
  field_number: fieldNumber,
});

export interface CurrentStateRequest { payor_guid: string; plan_guid: string | null; field_number: string }

export const currentConfigurationKey = (request: CurrentStateRequest): string =>
  `${request.payor_guid}|${request.plan_guid ?? ""}|${request.field_number}`;

export const currentOptionDiffers = (
  current: CurrentConfigurationResponse | null,
  proposedOption: PublicOptionCode,
): boolean => current !== null && current.effective_option_code !== proposedOption;

export const selectionsFromCurrent = (
  current: CurrentConfigurationResponse,
): CurrentSelections => {
  switch (current.effective_option_code) {
    case "SERVICE_FACILITY_ALWAYS_ADDRESS_YES":
      return { serviceMode: "always", serviceAddress: "yes", taxonomy: "no" };
    case "SERVICE_FACILITY_ALWAYS_ADDRESS_NO":
      return { serviceMode: "always", serviceAddress: "no", taxonomy: "no" };
    case "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES":
      return { serviceMode: "conditional", serviceAddress: "yes", taxonomy: "no" };
    case "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO":
      return { serviceMode: "conditional", serviceAddress: "no", taxonomy: "no" };
    case "SERVICE_FACILITY_NEVER":
      return { serviceMode: "never", serviceAddress: "no", taxonomy: "no" };
    case "PROVIDER_TAXONOMY_ON":
      return { serviceMode: "never", serviceAddress: "no", taxonomy: "yes" };
    case "PROVIDER_TAXONOMY_OFF":
      return { serviceMode: "never", serviceAddress: "no", taxonomy: "no" };
  }
};

export class CurrentConfigurationCache<T = CurrentConfigurationResponse> {
  private readonly values = new Map<string, T>();
  private readonly errors = new Map<string, unknown>();
  private readonly pending = new Map<string, Promise<T>>();
  private readonly listeners = new Set<() => void>();

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }
  private notify(): void { this.listeners.forEach((listener) => listener()); }
  peek(request: CurrentStateRequest): { status: "ready"; current: T } | { status: "loading" | "error" } {
    const key = currentConfigurationKey(request);
    const current = this.values.get(key);
    if (current !== undefined) return { status: "ready", current };
    return { status: this.errors.has(key) ? "error" : "loading" };
  }
  async load(request: CurrentStateRequest, loader: () => Promise<T>, force = false): Promise<T> {
    const key = currentConfigurationKey(request);
    if (!force) {
      const cached = this.values.get(key);
      if (cached !== undefined) return cached;
      const inFlight = this.pending.get(key);
      if (inFlight) return inFlight;
    }
    this.values.delete(key);
    this.errors.delete(key);
    const requestPromise = Promise.resolve().then(loader).then((response) => {
      // Invalidated requests may finish, but cannot resurrect or overwrite data.
      if (this.pending.get(key) === requestPromise) {
        this.values.set(key, response);
        this.notify();
      }
      return response;
    }).catch((error: unknown) => {
      if (this.pending.get(key) === requestPromise) {
        this.errors.set(key, error);
        this.notify();
      }
      throw error;
    }).finally(() => {
      if (this.pending.get(key) === requestPromise) this.pending.delete(key);
    });
    this.pending.set(key, requestPromise);
    this.notify();
    return requestPromise;
  }
  invalidate(request: CurrentStateRequest): void {
    const key = currentConfigurationKey(request);
    this.values.delete(key); this.errors.delete(key); this.pending.delete(key);
    this.notify();
  }
  clear(): void {
    this.values.clear(); this.errors.clear(); this.pending.clear();
    this.notify();
  }
}

export const currentConfigurationCache = new CurrentConfigurationCache();
