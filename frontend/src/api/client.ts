import type {
  ApiErrorBody,
  ApplyRequest,
  ConfigurationResponse,
  CurrentConfigurationRequest,
  CurrentConfigurationResponse,
  LineOfBusinessApplyRequest,
  LineOfBusinessChangeResponse,
  LineOfBusinessCurrentRequest,
  LineOfBusinessCurrentResponse,
  LineOfBusinessPreviewRequest,
  LineOfBusinessSaveRequest,
  LineOfBusinessSaveResponse,
  OptionsResponse,
  PreviewRequest,
} from "./types";

export class ApiClientError extends Error {
  constructor(
    public readonly category: string,
    message: string,
    public readonly status: number,
  ) {
    super(message);
  }
}

const request = async <T>(path: string, init?: RequestInit): Promise<T> => {
  let response: Response;
  try {
    response = await fetch(path, init);
  } catch {
    throw new ApiClientError(
      "backend_unavailable",
      "The configuration service is unavailable. Check that the backend is running and try again.",
      0,
    );
  }
  if (!response.ok) {
    let body: ApiErrorBody | null = null;
    try { body = (await response.json()) as ApiErrorBody; } catch { /* safe fallback */ }
    throw new ApiClientError(
      body?.error?.category ?? "server_failure",
      body?.error?.message ?? "The request could not be completed safely.",
      response.status,
    );
  }
  return response.json() as Promise<T>;
};

const post = (body: object): RequestInit => ({
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(body),
});

export const apiClient = {
  options: () => request<OptionsResponse>("/api/options"),
  current: (body: CurrentConfigurationRequest) =>
    request<CurrentConfigurationResponse>("/api/config/current", post(body)),
  preview: (body: PreviewRequest) =>
    request<ConfigurationResponse>("/api/config/preview", post(body)),
  apply: (body: ApplyRequest) =>
    request<ConfigurationResponse>("/api/config/apply", post(body)),
  lineOfBusinessCurrent: (body: LineOfBusinessCurrentRequest) =>
    request<LineOfBusinessCurrentResponse>("/api/config/line-of-business/current", post(body)),
  lineOfBusinessSave: (body: LineOfBusinessSaveRequest) =>
    request<LineOfBusinessSaveResponse>("/api/config/line-of-business/save", post(body)),
  lineOfBusinessPreviewChange: (body: LineOfBusinessPreviewRequest) =>
    request<LineOfBusinessChangeResponse>("/api/config/line-of-business/preview-change", post(body)),
  lineOfBusinessApplyChange: (body: LineOfBusinessApplyRequest) =>
    request<LineOfBusinessChangeResponse>("/api/config/line-of-business/apply-change", post(body)),
};
