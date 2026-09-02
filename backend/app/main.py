"""FastAPI entry point for the PFC Configuration Tool backend."""

from __future__ import annotations

from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse

from backend.app.errors import ApiError
from backend.app.models import (
    ApplyRequest,
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
)
from backend.app.services.configuration import ConfigurationService


app = FastAPI(title="PFC Configuration Tool API", version="0.1.0")


def get_configuration_service() -> ConfigurationService:
    return ConfigurationService()


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


@app.post("/api/config/apply", response_model=ConfigurationResponse)
def apply(
    request: ApplyRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.apply(**request.model_dump())
