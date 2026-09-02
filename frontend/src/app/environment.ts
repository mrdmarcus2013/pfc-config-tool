export interface FrontendEnvironment {
  readonly VITE_ENABLE_TECHNICAL_DETAILS?: unknown;
}

export const technicalDetailsEnabled = (value: unknown): boolean =>
  value === true || (typeof value === "string" && value.toLowerCase() === "true");

export const technicalDetailsEnabledFromEnvironment = (
  environment: FrontendEnvironment | undefined,
): boolean => technicalDetailsEnabled(
  environment?.VITE_ENABLE_TECHNICAL_DETAILS,
);

export const SUPPORT_DEVELOPER_MODE = technicalDetailsEnabledFromEnvironment(
  import.meta.env,
);
