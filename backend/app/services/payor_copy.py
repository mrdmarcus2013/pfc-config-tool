"""Thin transaction adapter for the Oracle payor-copy engine."""
import json
import logging
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


class PayorCopyService:
    def __init__(self, connection_factory=create_connection):
        self._connection_factory = connection_factory

    def destinations(self, request: CopyDestinationRequest) -> CopyDestinationsResponse:
        """Run the actual Oracle preview for candidates in one read-only snapshot."""
        connection = None
        try:
            connection = self._connection_factory()
            with connection.cursor() as cursor:
                cursor.execute("SET TRANSACTION READ ONLY")
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
        except oracledb.DatabaseError as exc:
            raise translate_oracle_error(exc, "copy eligibility") from None
        except DatabaseConfigurationError:
            raise ApiError(503, "database_failure", "The database connection is not configured.") from None
        except Exception as exc:
            logger.error("Copy eligibility failed (%s)", type(exc).__name__)
            raise ApiError(500, "application_failure", "Eligible destination payors could not be loaded.") from None
        finally:
            if connection is not None:
                try:
                    connection.rollback()
                finally:
                    connection.close()

    def run(self, request: CopyPreviewRequest, *, apply: bool = False) -> CopyResponse:
        connection = None
        try:
            connection = self._connection_factory()
            with connection.cursor() as cursor:
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
                connection.commit()
            else:
                connection.rollback()
            return response
        except oracledb.DatabaseError as exc:
            if connection is not None: connection.rollback()
            code = getattr(exc.args[0], "code", None)
            if code in COPY_ERRORS:
                raise ApiError(409, "stale_preview" if code == 20106 else "copy_blocked", COPY_ERRORS[code]) from None
            raise translate_oracle_error(exc, "payor copy") from None
        except DatabaseConfigurationError:
            if connection is not None: connection.rollback()
            raise ApiError(503, "database_failure", "The database connection is not configured.") from None
        except Exception as exc:
            if connection is not None: connection.rollback()
            logger.error("Payor copy failed (%s)", type(exc).__name__)
            raise ApiError(500, "application_failure", "The copy could not be completed safely. No changes were saved.") from None
        finally:
            if connection is not None: connection.close()
