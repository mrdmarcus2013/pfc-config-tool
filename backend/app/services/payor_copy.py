"""Thin transaction adapter for the Oracle payor-copy engine."""
import json
import logging
from collections.abc import Callable
from typing import Any

import oracledb

from backend.app.database import create_connection, DatabaseConfigurationError
from backend.app.errors import ApiError, translate_oracle_error
# Retain imports from this module for existing service clients.
from backend.app.models_payor_copy import (
    CopyApplyRequest as CopyApplyRequest,
    CopyChange as CopyChange,
    CopyContext as CopyContext,
    CopyDestination as CopyDestination,
    CopyDestinationRequest as CopyDestinationRequest,
    CopyDestinationsResponse as CopyDestinationsResponse,
    CopyPreviewRequest as CopyPreviewRequest,
    CopyResponse as CopyResponse,
)

logger = logging.getLogger(__name__)


def _copy_response(raw: Any) -> CopyResponse:
    """Decode the Oracle JSON result whether the driver returns text or a CLOB."""
    return CopyResponse.model_validate(json.loads(raw.read() if hasattr(raw, "read") else raw))


def _cleanup_safely(action: Callable[[], None], operation: str) -> None:
    """Cleanup must not replace a known result or the primary operation error."""
    try:
        action()
    except Exception as exc:
        logger.error("Payor copy %s cleanup failed (%s)", operation, type(exc).__name__)


COPY_ERRORS = {
    20100: "A valid copy request and audit identity are required.",
    20101: "Choose a destination payor different from the source.",
    20102: "Source and destination Line of Business must match.",
    20103: "The billing form must match the source for every destination context.",
    20104: "Ambiguous or unsupported claim settings require review before copying.",
    20105: "The destination cannot resolve the same complete configuration as the source. Review payor type and template compatibility.",
    20106: "The source or destination changed. Run Preview again before copying.",
    20107: "Copy verification failed. No changes were saved.",
    54: "Configuration is being changed by another session. Try Preview again shortly.",
}


COPY_SOURCE_ERRORS = {
    20100: "A valid source payor, optional plan, and audit identity are required.",
    20103: "The source billing form is not supported for copying.",
    20104: "The source payor or plan has missing, ambiguous, or unsupported claim settings. Review the source before copying.",
    20010: "The source configuration could not be resolved. Check the selected payor and plan ownership.",
    20011: "The source configuration is ambiguous or has a missing entry date. Review the source before copying.",
    20012: "The source inherits invalid claim settings. Correct its template or billing-form settings before copying.",
    20050: "The source payor was not found.",
    20053: "Save Line of Business for the source payor before copying.",
}


class PayorCopyService:
    def __init__(self, connection_factory=create_connection):
        self._connection_factory = connection_factory

    def destinations(self, request: CopyDestinationRequest) -> CopyDestinationsResponse:
        """Run the actual Oracle preview for candidates in one read-only snapshot."""
        connection = cursor = None
        try:
            connection = self._connection_factory()
            cursor = connection.cursor()
            cursor.execute("SET TRANSACTION READ ONLY")
            # Validate once even when there are no candidates. A source problem
            # must not be hidden by the per-destination blocker filtering below.
            try:
                cursor.execute("""BEGIN pfc_copy.validate_source(
                    :source_payor, :source_plan, :audit_user); END;""",
                    source_payor=request.source_payor_guid,
                    source_plan=request.source_plan_guid, audit_user=request.audit_user)
            except oracledb.DatabaseError as exc:
                code = getattr(exc.args[0], "code", None) if exc.args else None
                if code in COPY_SOURCE_ERRORS:
                    raise ApiError(409, "copy_source_blocked", COPY_SOURCE_ERRORS[code]) from None
                raise
            cursor.execute("""SELECT payor_guid, payor_name FROM payors
                WHERE payor_id LIKE 'SYN-%' AND payor_guid <> :source_payor
                ORDER BY payor_name, payor_guid""", source_payor=request.source_payor_guid)
            candidates = cursor.fetchall()
            destinations = []
            for payor_guid, payor_name in candidates:
                output = cursor.var(oracledb.DB_TYPE_CLOB)
                try:
                    cursor.execute("""BEGIN pfc_copy.run_copy(
                        :source_payor, :source_plan, :destination_payor, 'PREVIEW',
                        :audit_user, NULL, :result); END;""",
                        source_payor=request.source_payor_guid,
                        source_plan=request.source_plan_guid,
                        destination_payor=payor_guid, audit_user=request.audit_user,
                        result=output)
                except oracledb.DatabaseError as exc:
                    # Only known configuration blockers mean ineligible. Database
                    # failures must not masquerade as an empty destination list.
                    if getattr(exc.args[0], "code", None) in {
                        20101, 20102, 20103, 20104, 20105,
                        20010, 20011, 20012, 20020, 20021, 20050, 20053,
                    }:
                        continue
                    raise
                result = _copy_response(output.getvalue())
                if result.status not in {"READY", "NO_CHANGE"}:
                    raise ValueError("Unexpected eligibility response")
                destinations.append(CopyDestination(payor_guid=payor_guid, payor_name=payor_name))
            return CopyDestinationsResponse(destinations=destinations)
        except ApiError:
            raise
        except oracledb.DatabaseError as exc:
            raise translate_oracle_error(exc, "copy eligibility") from None
        except DatabaseConfigurationError:
            raise ApiError(503, "database_failure", "The database connection is not configured.") from None
        except Exception as exc:
            logger.error("Copy eligibility failed (%s)", type(exc).__name__)
            raise ApiError(500, "application_failure", "Eligible destination payors could not be loaded.") from None
        finally:
            if cursor is not None:
                _cleanup_safely(cursor.close, "cursor close")
            if connection is not None:
                _cleanup_safely(connection.rollback, "rollback")
                _cleanup_safely(connection.close, "connection close")

    def run(self, request: CopyPreviewRequest, *, apply: bool = False) -> CopyResponse:
        connection = cursor = None
        committed = False
        try:
            connection = self._connection_factory()
            cursor = connection.cursor()
            if not apply:
                cursor.execute("SET TRANSACTION READ ONLY")
            output = cursor.var(oracledb.DB_TYPE_CLOB)
            cursor.execute("""BEGIN pfc_copy.run_copy(
                :source_payor, :source_plan, :destination_payor, :mode,
                :audit_user, :expected_hash, :result); END;""",
                source_payor=request.source_payor_guid,
                source_plan=request.source_plan_guid,
                destination_payor=request.destination_payor_guid,
                mode="APPLY" if apply else "PREVIEW",
                audit_user=request.audit_user,
                expected_hash=getattr(request, "expected_state_hash", None),
                result=output)
            response = _copy_response(output.getvalue())
            if (apply and response.status != "APPLIED") or (not apply and response.status == "APPLIED"):
                raise ValueError("Unexpected copy operation response")
            if apply:
                # Ensure the complete response can be serialized before saving.
                response.model_dump_json()
                # Preserve the pre-commit cursor-close boundary. A failure here
                # still prevents committing; later connection cleanup does not.
                completed_cursor, cursor = cursor, None
                completed_cursor.close()
                connection.commit()
                committed = True
            return response
        except ApiError:
            raise
        except oracledb.DatabaseError as exc:
            code = getattr(exc.args[0], "code", None)
            if code in COPY_ERRORS:
                raise ApiError(409, "stale_preview" if code == 20106 else "copy_blocked", COPY_ERRORS[code]) from None
            raise translate_oracle_error(exc, "payor copy") from None
        except DatabaseConfigurationError:
            raise ApiError(503, "database_failure", "The database connection is not configured.") from None
        except Exception as exc:
            logger.error("Payor copy failed (%s)", type(exc).__name__)
            raise ApiError(500, "application_failure", "The copy could not be completed safely. No changes were saved.") from None
        finally:
            if cursor is not None:
                _cleanup_safely(cursor.close, "cursor close")
            if connection is not None:
                if not committed:
                    _cleanup_safely(connection.rollback, "rollback")
                _cleanup_safely(connection.close, "connection close")
