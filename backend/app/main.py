"""FastAPI entry point for the PFC Configuration Tool backend."""

from __future__ import annotations

from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse

from backend.app.errors import ApiError
from backend.app.models import (
    ApplyRequest,
    ConfigurationResponse,
    ErrorResponse,
    HealthResponse,
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


@app.post("/api/config/preview", response_model=ConfigurationResponse)
def preview(
    request: PreviewRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.preview(**request.model_dump())


@app.post("/api/config/apply", response_model=ConfigurationResponse)
def apply(
    request: ApplyRequest,
    service: ConfigurationService = Depends(get_configuration_service),
) -> dict[str, object]:
    return service.apply(**request.model_dump())
