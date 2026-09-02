"""Thin service adapter around the authoritative Oracle configuration procedure."""

from __future__ import annotations

import logging
from collections.abc import Callable
from typing import Any

import oracledb

from backend.app.database import DatabaseConfigurationError, create_connection
from backend.app.errors import ApiError, translate_oracle_error


logger = logging.getLogger(__name__)


OPTION_FIELDS = [
    {
        "field_number": "81",
        "field_label": "Provider Taxonomy",
        "options": [
            {
                "option_code": "PROVIDER_TAXONOMY_ON",
                "display_label": "Provider Taxonomy ON",
            },
            {
                "option_code": "PROVIDER_TAXONOMY_OFF",
                "display_label": "Provider Taxonomy OFF",
            },
        ],
    },
    {
        "field_number": "77",
        "field_label": "Service Facility",
        "options": [
            {
                "option_code": "SERVICE_FACILITY_ALWAYS_ADDRESS_YES",
                "display_label": "Always report service facility; report address",
            },
            {
                "option_code": "SERVICE_FACILITY_ALWAYS_ADDRESS_NO",
                "display_label": (
                    "Always report service facility; do not report address"
                ),
            },
            {
                "option_code": "SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES",
                "display_label": (
                    "Report service facility when care location is not HOME; "
                    "report address"
                ),
            },
            {
                "option_code": "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO",
                "display_label": (
                    "Report service facility when care location is not HOME; "
                    "do not report address"
                ),
            },
            {
                "option_code": "SERVICE_FACILITY_NEVER",
                "display_label": (
                    "Never report service facility; do not report address"
                ),
            },
        ],
    },
]

_OPTION_FIELD_NUMBERS = {
    option["option_code"]: field["field_number"]
    for field in OPTION_FIELDS
    for option in field["options"]
}

_APPLY_BLOCK = """
BEGIN
    pfc_line_of_business.require_defined(
        p_payor_guid => :payor_guid,
        p_lock => CASE WHEN :operation_mode = 'APPLY' THEN 'Y' ELSE 'N' END
    );
    pfc_apply_option(
        p_payor_guid          => :payor_guid,
        p_plan_guid           => :plan_guid,
        p_option_code         => :option_code,
        p_audit_user          => :audit_user,
        p_mode                => :operation_mode,
        p_expected_state_hash => :expected_state_hash,
        p_summary             => :summary_cursor,
        p_changes             => :changes_cursor
    );
END;
"""

_CURRENT_BLOCK = """
BEGIN
    pfc_line_of_business.require_defined(
        p_payor_guid => :payor_guid,
        p_lock => 'N'
    );
    pfc_get_current_config(
        p_payor_guid   => :payor_guid,
        p_plan_guid    => :plan_guid,
        p_field_number => :field_number,
        p_result       => :result_cursor
    );
END;
"""

_LOB_CURRENT_BLOCK = """
BEGIN
    pfc_line_of_business.get_current(
        p_payor_guid => :payor_guid,
        p_result => :result_cursor
    );
END;
"""

_LOB_SAVE_BLOCK = """
BEGIN
    pfc_line_of_business.save_initial(
        p_payor_guid => :payor_guid,
        p_line_of_business => :line_of_business,
        p_audit_user => :audit_user,
        p_result => :result_cursor
    );
END;
"""

_LOB_PREVIEW_BLOCK = """
BEGIN
    pfc_line_of_business.preview_change(
        p_payor_guid => :payor_guid,
        p_requested_line_of_business => :requested_line_of_business,
        p_summary => :summary_cursor,
        p_target_counts => :targets_cursor
    );
END;
"""

_LOB_APPLY_BLOCK = """
BEGIN
    pfc_line_of_business.apply_change(
        p_payor_guid => :payor_guid,
        p_requested_line_of_business => :requested_line_of_business,
        p_expected_state_hash => :expected_state_hash,
        p_audit_user => :audit_user,
        p_summary => :summary_cursor,
        p_target_counts => :targets_cursor
    );
END;
"""

_CURRENT_OPTION_FIELDS = {
    option["option_code"]: field["field_number"]
    for field in OPTION_FIELDS
    for option in field["options"]
}


def _rows_as_dicts(cursor: Any) -> list[dict[str, Any]]:
    columns = [description[0].lower() for description in cursor.description]
    return [dict(zip(columns, row, strict=True)) for row in cursor.fetchall()]


def _safe_summary(status: str, change_count: int) -> str:
    if status == "NO_CHANGE":
        return "No configuration change is required."
    if status == "PREVIEW":
        return f"{change_count} configuration change(s) are ready for review."
    return f"The configuration was updated with {change_count} change(s)."


def _rollback_after_error(connection: Any) -> None:
    try:
        connection.rollback()
    except Exception:
        logger.error("Oracle rollback failed while handling an operation error")


def _close_safely(resource: Any, resource_name: str) -> None:
    try:
        resource.close()
    except Exception:
        logger.error("Oracle %s close failed", resource_name)


class ConfigurationService:
    """Open one connection per call and delegate all configuration logic to Oracle."""

    def __init__(
        self,
        connection_factory: Callable[[], Any] = create_connection,
    ) -> None:
        self._connection_factory = connection_factory

    def health(self) -> dict[str, str]:
        connection = None
        cursor = None
        try:
            connection = self._connection_factory()
            cursor = connection.cursor()
            cursor.execute("SELECT 1 FROM dual")
            cursor.fetchone()
            return {"application": "ok", "oracle": "connected"}
        except (oracledb.DatabaseError, DatabaseConfigurationError):
            return {"application": "ok", "oracle": "unavailable"}
        finally:
            if cursor is not None:
                _close_safely(cursor, "health cursor")
            if connection is not None:
                _close_safely(connection, "health connection")

    def list_options(self) -> dict[str, Any]:
        # This is presentation metadata only. Oracle remains authoritative for
        # option existence, validation, target resolution, and desired state.
        return {"fields": OPTION_FIELDS}

    def line_of_business_current(self, *, payor_guid: str) -> dict[str, Any]:
        return self._run_lob_single(
            block=_LOB_CURRENT_BLOCK,
            binds={"payor_guid": payor_guid},
            operation="current Line of Business",
            commit=False,
            expected_status="UNDEFINED",
        )

    def line_of_business_save(
        self, *, payor_guid: str, line_of_business: str, audit_user: str
    ) -> dict[str, Any]:
        return self._run_lob_single(
            block=_LOB_SAVE_BLOCK,
            binds={
                "payor_guid": payor_guid,
                "line_of_business": line_of_business,
                "audit_user": audit_user,
            },
            operation="initial Line of Business save",
            commit=True,
            expected_status="SAVED",
        )

    def line_of_business_preview_change(
        self, *, payor_guid: str, requested_line_of_business: str
    ) -> dict[str, Any]:
        return self._run_lob_change(
            block=_LOB_PREVIEW_BLOCK,
            binds={
                "payor_guid": payor_guid,
                "requested_line_of_business": requested_line_of_business,
            },
            operation="Line of Business change preview",
            commit=False,
        )

    def line_of_business_apply_change(
        self,
        *,
        payor_guid: str,
        requested_line_of_business: str,
        expected_state_hash: str,
        audit_user: str,
    ) -> dict[str, Any]:
        return self._run_lob_change(
            block=_LOB_APPLY_BLOCK,
            binds={
                "payor_guid": payor_guid,
                "requested_line_of_business": requested_line_of_business,
                "expected_state_hash": expected_state_hash,
                "audit_user": audit_user,
            },
            operation="Line of Business change apply",
            commit=True,
        )

    def _run_lob_single(
        self,
        *,
        block: str,
        binds: dict[str, Any],
        operation: str,
        commit: bool,
        expected_status: str,
    ) -> dict[str, Any]:
        connection = cursor = result_cursor = None
        try:
            connection = self._connection_factory()
            cursor = connection.cursor()
            result_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(block, **binds, result_cursor=result_out)
            result_cursor = result_out.getvalue()
            rows = _rows_as_dicts(result_cursor)
            if len(rows) != 1:
                raise ApiError(500, "application_failure", "The database returned an invalid Line of Business result.")
            row = rows[0]
            status = str(row.get("status"))
            lob = row.get("line_of_business")
            valid = (
                (expected_status == "UNDEFINED" and status in {"UNDEFINED", "DEFINED"})
                or status == expected_status
            ) and lob in {None, "HOME_HEALTH", "HOSPICE"}
            if not valid or (status == "DEFINED" and lob is None) or (status == "SAVED" and lob is None):
                raise ApiError(500, "application_failure", "The database returned an invalid Line of Business result.")
            response = {"status": status, "line_of_business": lob}
            if commit:
                connection.commit()
            else:
                connection.rollback()
            return response
        except ApiError:
            if connection is not None: _rollback_after_error(connection)
            raise
        except oracledb.DatabaseError as exc:
            if connection is not None: _rollback_after_error(connection)
            raise translate_oracle_error(exc, operation) from None
        except DatabaseConfigurationError as exc:
            if connection is not None: _rollback_after_error(connection)
            raise ApiError(503, "database_failure", "The database connection is not configured.") from exc
        except Exception as exc:
            if connection is not None: _rollback_after_error(connection)
            logger.error("Unexpected LOB adapter failure (%s)", type(exc).__name__)
            raise ApiError(500, "application_failure", "The Line of Business operation failed safely.") from None
        finally:
            if result_cursor is not None: _close_safely(result_cursor, "LOB result cursor")
            if cursor is not None: _close_safely(cursor, "LOB procedure cursor")
            if connection is not None: _close_safely(connection, "LOB connection")

    def _run_lob_change(
        self,
        *,
        block: str,
        binds: dict[str, Any],
        operation: str,
        commit: bool,
    ) -> dict[str, Any]:
        connection = cursor = summary_cursor = targets_cursor = None
        try:
            connection = self._connection_factory()
            cursor = connection.cursor()
            summary_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            targets_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(block, **binds, summary_cursor=summary_out, targets_cursor=targets_out)
            summary_cursor = summary_out.getvalue()
            targets_cursor = targets_out.getvalue()
            summaries = _rows_as_dicts(summary_cursor)
            targets = _rows_as_dicts(targets_cursor)
            if len(summaries) != 1:
                raise ApiError(500, "application_failure", "The database returned an invalid Line of Business result.")
            row = summaries[0]
            status = str(row.get("status"))
            allowed = {"APPLIED", "NO_CHANGE"} if commit else {"CHANGES_REQUIRED", "NO_CHANGE"}
            if status not in allowed or row.get("current_line_of_business") not in {"HOME_HEALTH", "HOSPICE"} or row.get("requested_line_of_business") not in {"HOME_HEALTH", "HOSPICE"}:
                raise ApiError(500, "application_failure", "The database returned an invalid Line of Business result.")
            state_hash = str(row.get("preview_state_hash", ""))
            if len(state_hash) != 64:
                raise ApiError(500, "application_failure", "The database returned an invalid Line of Business result.")
            response = {
                "status": status,
                "changes_required": row.get("changes_required") == "Y",
                "current_line_of_business": row["current_line_of_business"],
                "requested_line_of_business": row["requested_line_of_business"],
                "managed_target_count": int(row["managed_target_count"]),
                "affected_managed_target_count": int(row["affected_managed_target_count"]),
                "managed_her_count": int(row["managed_her_count"]),
                "managed_hef_count": int(row["managed_hef_count"]),
                "preview_state_hash": state_hash,
                "summary": (
                    "No Line of Business change is required."
                    if status == "NO_CHANGE"
                    else f"{int(row['affected_managed_target_count'])} customized claim-field component(s) will be reset."
                    if status == "CHANGES_REQUIRED"
                    else "Line of Business changed and managed claim-field customizations were reset."
                ),
                "debug_targets": [
                    {
                        "billing_form_code": str(target["billing_form_code"]),
                        "record_type_code": str(target["record_type_code"]),
                        "her_count": int(target["her_count"]),
                        "hef_count": int(target["hef_count"]),
                    }
                    for target in targets
                ],
            }
            if commit: connection.commit()
            else: connection.rollback()
            return response
        except ApiError:
            if connection is not None: _rollback_after_error(connection)
            raise
        except oracledb.DatabaseError as exc:
            if connection is not None: _rollback_after_error(connection)
            raise translate_oracle_error(exc, operation) from None
        except DatabaseConfigurationError as exc:
            if connection is not None: _rollback_after_error(connection)
            raise ApiError(503, "database_failure", "The database connection is not configured.") from exc
        except Exception as exc:
            if connection is not None: _rollback_after_error(connection)
            logger.error("Unexpected LOB change adapter failure (%s)", type(exc).__name__)
            raise ApiError(500, "application_failure", "The Line of Business operation failed safely.") from None
        finally:
            if targets_cursor is not None: _close_safely(targets_cursor, "LOB target cursor")
            if summary_cursor is not None: _close_safely(summary_cursor, "LOB summary cursor")
            if cursor is not None: _close_safely(cursor, "LOB procedure cursor")
            if connection is not None: _close_safely(connection, "LOB connection")

    def preview(
        self,
        *,
        payor_guid: str,
        plan_guid: str | None,
        option_code: str,
        audit_user: str,
    ) -> dict[str, Any]:
        return self._run_option(
            payor_guid=payor_guid,
            plan_guid=plan_guid,
            option_code=option_code,
            audit_user=audit_user,
            mode="PREVIEW",
            expected_state_hash=None,
        )

    def current(
        self,
        *,
        payor_guid: str,
        plan_guid: str | None,
        field_number: str,
    ) -> dict[str, Any]:
        connection = None
        cursor = None
        result_cursor = None
        try:
            connection = self._connection_factory()
            cursor = connection.cursor()
            result_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(
                _CURRENT_BLOCK,
                payor_guid=payor_guid,
                plan_guid=plan_guid,
                field_number=field_number,
                result_cursor=result_out,
            )
            result_cursor = result_out.getvalue()
            rows = _rows_as_dicts(result_cursor)
            if len(rows) != 1:
                raise ApiError(
                    status_code=500,
                    category="application_failure",
                    message="The database returned an invalid current-state result.",
                )
            response = self._current_response(rows[0], field_number)
            connection.rollback()
            return response
        except ApiError:
            if connection is not None:
                _rollback_after_error(connection)
            raise
        except oracledb.DatabaseError as exc:
            if connection is not None:
                _rollback_after_error(connection)
            raise translate_oracle_error(exc, "current configuration") from None
        except DatabaseConfigurationError as exc:
            if connection is not None:
                _rollback_after_error(connection)
            raise ApiError(
                status_code=503,
                category="database_failure",
                message="The database connection is not configured.",
            ) from exc
        except Exception as exc:
            if connection is not None:
                _rollback_after_error(connection)
            logger.error("Unexpected current-state adapter failure (%s)", type(exc).__name__)
            raise ApiError(
                status_code=500,
                category="application_failure",
                message="The current configuration could not be resolved safely.",
            ) from None
        finally:
            if result_cursor is not None:
                _close_safely(result_cursor, "current-state result cursor")
            if cursor is not None:
                _close_safely(cursor, "current-state procedure cursor")
            if connection is not None:
                _close_safely(connection, "current-state connection")

    def apply(
        self,
        *,
        payor_guid: str,
        plan_guid: str | None,
        option_code: str,
        audit_user: str,
        expected_state_hash: str,
    ) -> dict[str, Any]:
        return self._run_option(
            payor_guid=payor_guid,
            plan_guid=plan_guid,
            option_code=option_code,
            audit_user=audit_user,
            mode="APPLY",
            expected_state_hash=expected_state_hash,
        )

    def _run_option(
        self,
        *,
        payor_guid: str,
        plan_guid: str | None,
        option_code: str,
        audit_user: str,
        mode: str,
        expected_state_hash: str | None,
    ) -> dict[str, Any]:
        connection = None
        cursor = None
        summary_cursor = None
        changes_cursor = None
        try:
            connection = self._connection_factory()
            cursor = connection.cursor()
            summary_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            changes_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(
                _APPLY_BLOCK,
                payor_guid=payor_guid,
                plan_guid=plan_guid,
                option_code=option_code,
                audit_user=audit_user,
                operation_mode=mode,
                expected_state_hash=expected_state_hash,
                summary_cursor=summary_out,
                changes_cursor=changes_out,
            )
            summary_cursor = summary_out.getvalue()
            changes_cursor = changes_out.getvalue()
            summaries = _rows_as_dicts(summary_cursor)
            changes = _rows_as_dicts(changes_cursor)

            if len(summaries) != 1:
                raise ApiError(
                    status_code=500,
                    category="application_failure",
                    message="The database returned an invalid operation result.",
                )

            summary = summaries[0]
            status = str(summary["status"])
            expected_statuses = {"PREVIEW", "NO_CHANGE"} if mode == "PREVIEW" else {"APPLIED", "NO_CHANGE"}
            if status not in expected_statuses:
                raise ApiError(
                    status_code=500,
                    category="application_failure",
                    message="The database returned an invalid operation status.",
                )

            response = self._response(summary, changes)
            if mode == "APPLY":
                connection.commit()
            else:
                connection.rollback()
            return response
        except ApiError:
            if connection is not None:
                _rollback_after_error(connection)
            raise
        except oracledb.DatabaseError as exc:
            if connection is not None:
                _rollback_after_error(connection)
            raise translate_oracle_error(exc, mode.lower()) from None
        except DatabaseConfigurationError as exc:
            if connection is not None:
                _rollback_after_error(connection)
            raise ApiError(
                status_code=503,
                category="database_failure",
                message="The database connection is not configured.",
            ) from exc
        except Exception as exc:
            if connection is not None:
                _rollback_after_error(connection)
            logger.error(
                "Unexpected %s adapter failure (%s)",
                mode.lower(),
                type(exc).__name__,
            )
            raise ApiError(
                status_code=500,
                category="application_failure",
                message="The configuration operation failed safely.",
            ) from None
        finally:
            if changes_cursor is not None:
                _close_safely(changes_cursor, "changes cursor")
            if summary_cursor is not None:
                _close_safely(summary_cursor, "summary cursor")
            if cursor is not None:
                _close_safely(cursor, "procedure cursor")
            if connection is not None:
                _close_safely(connection, "procedure connection")

    @staticmethod
    def _response(summary: dict[str, Any], changes: list[dict[str, Any]]) -> dict[str, Any]:
        option_code = str(summary["option_code"])
        status = str(summary["status"])
        change_count = int(summary["change_count"])
        return {
            "status": status,
            "option_code": option_code,
            "display_label": str(summary["display_label"]),
            "field_number": _OPTION_FIELD_NUMBERS.get(option_code),
            "state_hash": str(summary["state_hash"]),
            "change_count": change_count,
            "summary": _safe_summary(status, change_count),
            "pfc_guid": summary.get("pfc_guid"),
            "debug_changes": [
                {
                    "operation_order": int(change["operation_order"]),
                    "operation_code": str(change["operation_code"]),
                    "target_identifier": change.get("target_electronic_rec_guid"),
                    "field_number": change.get("field_number"),
                }
                for change in changes
            ],
        }

    @staticmethod
    def _current_response(row: dict[str, Any], requested_field: str) -> dict[str, Any]:
        status = str(row.get("status"))
        field_number = str(row.get("field_number"))
        capability = str(row.get("capability"))
        option_code = str(row.get("effective_option_code"))
        expected_capability = {
            "77": "service-facility",
            "81": "provider-taxonomy",
        }.get(requested_field)
        if (
            status != "RESOLVED"
            or field_number != requested_field
            or capability != expected_capability
            or _CURRENT_OPTION_FIELDS.get(option_code) != requested_field
            or not row.get("pfc_guid")
        ):
            raise ApiError(
                status_code=500,
                category="application_failure",
                message="The database returned an invalid current-state result.",
            )

        canonical_value = row.get("is_canonical")
        if canonical_value not in (None, "Y", "N"):
            raise ApiError(500, "application_failure", "The database returned an invalid current-state result.")

        if requested_field == "77":
            mode = row.get("mode")
            report_address = row.get("report_address")
            if mode not in ("ALWAYS", "CONDITIONAL", "NEVER") or report_address not in ("Y", "N"):
                raise ApiError(500, "application_failure", "The database returned an invalid current-state result.")
            display = {"mode": mode, "report_address": report_address, "enabled": None}
        else:
            enabled = row.get("enabled")
            if enabled not in ("Y", "N"):
                raise ApiError(500, "application_failure", "The database returned an invalid current-state result.")
            display = {"mode": None, "report_address": None, "enabled": enabled == "Y"}

        return {
            "status": status,
            "field_number": field_number,
            "capability": capability,
            "effective_option_code": option_code,
            "display": display,
            "pfc_guid": str(row["pfc_guid"]),
            "canonical": None if canonical_value is None else canonical_value == "Y",
        }
