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

export const currentConfigurationKey = (request: CurrentConfigurationRequest): string =>
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

export class CurrentConfigurationCache {
  private readonly values = new Map<string, CurrentConfigurationResponse>();
  private readonly pending = new Map<string, Promise<CurrentConfigurationResponse>>();

  async load(
    request: CurrentConfigurationRequest,
    loader: () => Promise<CurrentConfigurationResponse>,
    force = false,
  ): Promise<CurrentConfigurationResponse> {
    const key = currentConfigurationKey(request);
    if (!force) {
      const cached = this.values.get(key);
      if (cached) return cached;
      const inFlight = this.pending.get(key);
      if (inFlight) return inFlight;
    }
    const requestPromise = loader().then((response) => {
      this.values.set(key, response);
      return response;
    }).finally(() => {
      if (this.pending.get(key) === requestPromise) this.pending.delete(key);
    });
    this.pending.set(key, requestPromise);
    return requestPromise;
  }

  invalidate(request: CurrentConfigurationRequest): void {
    const key = currentConfigurationKey(request);
    this.values.delete(key);
    this.pending.delete(key);
  }

  clear(): void {
    this.values.clear();
    this.pending.clear();
  }
}

export const currentConfigurationCache = new CurrentConfigurationCache();
