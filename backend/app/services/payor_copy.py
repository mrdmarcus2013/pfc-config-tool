"""Thin transaction adapter for the Oracle payor-copy engine."""
import json
import logging

import oracledb
from pydantic import BaseModel, ConfigDict, Field
from typing import Literal

from backend.app.database import create_connection, DatabaseConfigurationError
from backend.app.errors import ApiError, translate_oracle_error
from backend.app.models import GuidText

logger = logging.getLogger(__name__)


class CopyDestinationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    source_payor_guid: GuidText
    source_plan_guid: GuidText | None = None
    audit_user: GuidText


class CopyPreviewRequest(CopyDestinationRequest):
    destination_payor_guid: GuidText


class CopyDestination(BaseModel):
    payor_guid: str
    payor_name: str


class CopyDestinationsResponse(BaseModel):
    destinations: list[CopyDestination]


class CopyApplyRequest(CopyPreviewRequest):
    expected_state_hash: str = Field(pattern=r"^[A-Fa-f0-9]{64}$")


class CopyContext(BaseModel):
    pfc_guid: str
    plan_guid: str | None
    label: str
    templates_changed: bool
    form_template_before: str = "Unavailable"
    user_template_before: str = "Unavailable"


class CopyChange(BaseModel):
    label: str
    action: Literal["KEEP", "REMOVE", "COPY"]
    level: str
    record_type: str


class CopyResponse(BaseModel):
    status: Literal["READY", "NO_CHANGE", "APPLIED"]
    state_hash: str
    source_pfc_guid: str
    billing_form_code: str
    line_of_business: Literal["HOME_HEALTH", "HOSPICE"]
    source_form_template: str = "Unavailable"
    source_user_template: str = "Unavailable"
    records_copied: int
    records_kept: int
    records_normalized: int = 0
    records_removed: int
    plan_records_removed: int
    fields_copied: int
    fields_removed: int
    template_contexts_updated: int
    contexts: list[CopyContext]
    changes: list[CopyChange]


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
                    raw = output.getvalue()
                    result = CopyResponse.model_validate(json.loads(raw.read() if hasattr(raw, "read") else raw))
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
                raw = output.getvalue()
                response = CopyResponse.model_validate(json.loads(raw.read() if hasattr(raw, "read") else raw))
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
