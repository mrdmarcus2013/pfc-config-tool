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
]

_OPTION_FIELD_NUMBERS = {
    option["option_code"]: field["field_number"]
    for field in OPTION_FIELDS
    for option in field["options"]
}

_APPLY_BLOCK = """
BEGIN
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
