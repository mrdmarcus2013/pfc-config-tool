"""FastAPI entry point for the PFC Configuration Tool backend."""

from __future__ import annotations

from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse

from backend.app.errors import ApiError
from backend.app.models import (
    ApplyRequest,
    ConfigurationContextRequest,
    ConfigurationContextResponse,
    ConfigurationOverviewResponse,
    ConfigurationResponse,
    CurrentConfigurationRequest,
    CurrentConfigurationResponse,
    ErrorResponse,
    HealthResponse,
    LineOfBusinessApplyRequest,
    LineOfBusinessChangeResponse,
    LineOfBusinessCurrentRequest,
    LineOfBusinessCurrentResponse,
    LineOfBusinessPreviewRequest,
    LineOfBusinessSaveRequest,
    LineOfBusinessSaveResponse,
    OptionsResponse,
    PreviewRequest,
    RemarksApplyRequest,
    RemarksChangeRequest,
    RemarksChangeResponse,
    RemarksCurrentRequest,
    RemarksCurrentResponse,
    SupportPayorContextsResponse,
    ValueCodesApplyRequest,
    ValueCodesChangeRequest,
    ValueCodesChangeResponse,
    ValueCodesCurrentRequest,
    ValueCodesCurrentResponse,
)
from backend.app.services.configuration import ConfigurationService


app = FastAPI(title="PFC Configuration Tool API", version="0.1.0")


def get_configuration_service() -> ConfigurationService:
    return ConfigurationService()


@app.post("/api/config/overview", response_model=ConfigurationOverviewResponse)
def configuration_overview(
    request: ConfigurationContextRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.overview(**request.model_dump())


@app.exception_handler(ApiError)
async def api_error_handler(_: Request, exc: ApiError) -> JSONResponse:
    body = ErrorResponse(error={"category": exc.category, "message": exc.message})
    return JSONResponse(status_code=exc.status_code, content=body.model_dump())


@app.get("/api/health", response_model=HealthResponse)
def health(
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, str]:
    return service.health()


@app.get("/api/options", response_model=OptionsResponse)
def options(
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.list_options()


@app.get(
    "/api/support/payor-contexts",
    response_model=SupportPayorContextsResponse,
)
def support_payor_contexts(
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.list_support_payor_contexts()


@app.post(
    "/api/config/line-of-business/current",
    response_model=LineOfBusinessCurrentResponse,
)
def current_line_of_business(
    request: LineOfBusinessCurrentRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.line_of_business_current(**request.model_dump())


@app.post(
    "/api/config/line-of-business/save",
    response_model=LineOfBusinessSaveResponse,
)
def save_line_of_business(
    request: LineOfBusinessSaveRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.line_of_business_save(**request.model_dump())


@app.post(
    "/api/config/line-of-business/preview-change",
    response_model=LineOfBusinessChangeResponse,
)
def preview_line_of_business_change(
    request: LineOfBusinessPreviewRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.line_of_business_preview_change(**request.model_dump())


@app.post(
    "/api/config/line-of-business/apply-change",
    response_model=LineOfBusinessChangeResponse,
)
def apply_line_of_business_change(
    request: LineOfBusinessApplyRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.line_of_business_apply_change(**request.model_dump())


@app.post("/api/config/preview", response_model=ConfigurationResponse)
def preview(
    request: PreviewRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.preview(**request.model_dump())


@app.post("/api/config/current", response_model=CurrentConfigurationResponse)
def current_configuration(
    request: CurrentConfigurationRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.current(**request.model_dump())


@app.post("/api/config/context", response_model=ConfigurationContextResponse)
def configuration_context(
    request: ConfigurationContextRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.configuration_context(**request.model_dump())


@app.post("/api/config/apply", response_model=ConfigurationResponse)
def apply(
    request: ApplyRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.apply(**request.model_dump())


@app.post("/api/config/value-codes/current", response_model=ValueCodesCurrentResponse)
def current_value_codes(
    request: ValueCodesCurrentRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.value_codes_current(**request.model_dump())


@app.post("/api/config/value-codes/preview", response_model=ValueCodesChangeResponse)
def preview_value_codes(
    request: ValueCodesChangeRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.value_codes_preview(**request.model_dump())


@app.post("/api/config/value-codes/apply", response_model=ValueCodesChangeResponse)
def apply_value_codes(
    request: ValueCodesApplyRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.value_codes_apply(**request.model_dump())


@app.post("/api/config/remarks/current", response_model=RemarksCurrentResponse)
def current_remarks(
    request: RemarksCurrentRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.remarks_current(**request.model_dump())


@app.post("/api/config/remarks/preview", response_model=RemarksChangeResponse)
def preview_remarks(
    request: RemarksChangeRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.remarks_preview(**request.model_dump())


@app.post("/api/config/remarks/apply", response_model=RemarksChangeResponse)
def apply_remarks(
    request: RemarksApplyRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.remarks_apply(**request.model_dump())
