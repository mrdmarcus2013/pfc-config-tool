"""Safe application errors and Oracle error translation."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any


logger = logging.getLogger(__name__)


@dataclass(slots=True)
class ApiError(Exception):
    """An error that is safe to return through the API."""

    status_code: int
    category: str
    message: str

    def __post_init__(self) -> None:
        Exception.__init__(self, self.message)


_ORACLE_ERROR_MAP: dict[int, tuple[int, str, str]] = {
    20001: (404, "option_not_found", "The requested configuration option was not found."),
    20010: (404, "configuration_not_found", "No configuration context was found for that request."),
    20011: (409, "ambiguous_target", "The configuration target is ambiguous and cannot be changed safely."),
    20020: (409, "source_not_found", "No eligible configuration source was found."),
    20021: (409, "ambiguous_source", "The configuration source is ambiguous and cannot be used safely."),
    20012: (409, "invalid_inherited_configuration", "The inherited claim configuration is invalid and must be corrected before this field can use Default."),
    20030: (400, "invalid_request", "The requested operation mode is invalid."),
    20031: (400, "invalid_request", "A valid audit user is required."),
    20032: (500, "application_failure", "The selected option is not configured correctly."),
    20033: (409, "target_not_found", "No target mapping was found for the selected option."),
    20034: (409, "ambiguous_target", "Multiple target mappings were found for the selected option."),
    20035: (400, "invalid_request", "An expected state hash is required before applying changes."),
    20036: (409, "stale_preview", "The preview is stale. Preview the change again before applying it."),
    20037: (409, "target_not_found", "A required option target was not found."),
    20038: (409, "ambiguous_target", "A required option target is ambiguous."),
    20039: (500, "verification_failure", "The configuration change could not be verified."),
    20040: (500, "application_failure", "The configuration operation failed safely."),
    20041: (409, "current_state_unsupported", "The current effective configuration is inconsistent or unsupported."),
    20042: (422, "unsupported_field", "Current configuration is not available for that field."),
    20050: (404, "payor_not_found", "The requested payor was not found."),
    20051: (400, "invalid_request", "Select Home Health or Hospice."),
    20052: (409, "line_of_business_already_saved", "Line of Business is already saved for this payor."),
    20053: (409, "line_of_business_required", "Line of Business must be saved before claim fields can be configured."),
    20054: (400, "invalid_request", "Preview the Line of Business change before applying it."),
    20055: (409, "stale_preview", "The reset preview is stale. Preview the Line of Business change again."),
    20056: (500, "verification_failure", "The Line of Business change could not be verified and was rolled back."),
    20057: (500, "application_failure", "The Line of Business operation failed safely."),
    20060: (409, "line_of_business_required", "Line of Business must be saved before Value Codes can be configured."),
    20061: (422, "invalid_selection", "The saved Line of Business is not supported for Value Codes."),
    20062: (422, "invalid_selection", "The Value Codes selections are not valid for the saved Line of Business."),
    20063: (409, "current_state_unsupported", "The Value Codes configuration cannot be processed safely."),
    20070: (409, "line_of_business_required", "Line of Business must be saved before Remarks can be configured."),
    20071: (422, "invalid_selection", "The saved Line of Business is not supported for Remarks."),
    20072: (422, "invalid_request", "Select Default or Custom remark."),
    20073: (422, "invalid_request", "Custom remark text is required."),
    20074: (422, "invalid_request", "Custom remark text exceeds the configured maximum length."),
    20075: (409, "current_state_unsupported", "The Remarks configuration cannot be processed safely."),
}


def _oracle_code(exc: BaseException) -> int | None:
    """Extract an Oracle error code without retaining its potentially sensitive text."""

    details: Any = exc.args[0] if exc.args else None
    code = getattr(details, "code", None)
    if code is None:
        return None
    try:
        return abs(int(code))
    except (TypeError, ValueError):
        return None


def translate_oracle_error(exc: BaseException, operation: str) -> ApiError:
    """Map known Oracle application errors to stable, user-safe API errors."""

    code = _oracle_code(exc)
    mapping = _ORACLE_ERROR_MAP.get(code) if code is not None else None
    logger.error("Oracle %s failed (code=%s)", operation, code or "unknown")

    if mapping is None:
        return ApiError(
            status_code=503,
            category="database_failure",
            message="The database operation could not be completed.",
        )

    status_code, category, message = mapping
    return ApiError(status_code=status_code, category=category, message=message)
