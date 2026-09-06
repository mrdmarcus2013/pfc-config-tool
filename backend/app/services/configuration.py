"""Thin service adapter around the authoritative Oracle configuration procedure."""

from __future__ import annotations

import json
import logging
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from typing import Any

import oracledb
from pydantic import BaseModel

from backend.app.database import DatabaseConfigurationError, create_connection
from backend.app.errors import ApiError, translate_oracle_error
from backend.app.models import (
    ConfigurationResponse,
    LineOfBusinessChangeResponse,
    LineOfBusinessCurrentResponse,
    LineOfBusinessSaveResponse,
    RemarksChangeResponse,
    ValueCodesChangeResponse,
)


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
    {
        "field_number": "39-41",
        "field_label": "Value Codes",
        "options": [],
    },
    {
        "field_number": "80",
        "field_label": "Remarks",
        "options": [],
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

_CONTEXT_BLOCK = """
DECLARE
    l_resolution pfc_config_internal.t_pfc_resolution;
BEGIN
    pfc_config_internal.resolve_pfc(
        p_payor_guid => :payor_guid,
        p_plan_guid => :plan_guid,
        p_resolution => l_resolution
    );
    :resolved_payor_guid := l_resolution.payor_guid;
    :resolved_plan_guid := l_resolution.plan_guid;
    :pfc_guid := l_resolution.pfc_guid;
    :billing_form_code := l_resolution.billing_form_code;
    :form_template_guid := l_resolution.form_template_guid;
    :user_form_template_guid := l_resolution.user_form_template_guid;
    SELECT (SELECT template_name FROM pfc_config_form_templates
            WHERE form_template_guid = l_resolution.form_template_guid),
           (SELECT template_name FROM pfc_config_user_templates
            WHERE user_form_template_guid = l_resolution.user_form_template_guid)
    INTO :form_template_name, :user_form_template_name
    FROM dual;
END;
"""

# The selector is intentionally limited to local synthetic POC payors. A
# production catalog requires host-authenticated Tier 2 authorization.
_SUPPORT_PAYOR_CONTEXTS_QUERY = """
SELECT DISTINCT
    payor.payor_guid,
    payor.payor_name,
    payor.payor_id,
    target.plan_guid,
    plans.plan_name
FROM payors payor
JOIN pfc target
  ON target.payor_guid = payor.payor_guid
LEFT JOIN pfc_config_plans plans ON plans.plan_guid = target.plan_guid AND plans.payor_guid = payor.payor_guid
WHERE payor.payor_id LIKE 'SYN-%'
  AND target.cpd_end_date > SYSDATE
  AND target.default_media_type = 'E'
  AND target.type_of_bill IS NULL
  AND target.billing_form_code = '837I_5010'
ORDER BY payor.payor_name, payor.payor_guid, target.plan_guid NULLS FIRST
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

_VALUE_CODES_CURRENT_BLOCK = """
BEGIN
    pfc_value_codes_api.current_configuration(
        p_payor_guid => :payor_guid, p_plan_guid => :plan_guid,
        p_result => :result_cursor
    );
END;
"""

_VALUE_CODES_CHANGE_BLOCK = """
BEGIN
    IF :operation_mode = 'PREVIEW' THEN
        pfc_value_codes_api.preview_configuration(
            :payor_guid, :plan_guid, :cbsa, :fips,
            :care_location_value_code, :patient_entered_value_code,
            :covered_days_value_code, :audit_user,
            :summary_cursor, :changes_cursor
        );
    ELSE
        pfc_value_codes_api.apply_configuration(
            :payor_guid, :plan_guid, :cbsa, :fips,
            :care_location_value_code, :patient_entered_value_code,
            :covered_days_value_code, :audit_user, :expected_state_hash,
            :summary_cursor, :changes_cursor
        );
    END IF;
END;
"""

_REMARKS_CURRENT_BLOCK = """
BEGIN
    pfc_remarks_api.current_configuration(
        p_payor_guid => :payor_guid, p_plan_guid => :plan_guid,
        p_result => :result_cursor
    );
END;
"""

_REMARKS_CHANGE_BLOCK = """
BEGIN
    IF :operation_mode = 'PREVIEW' THEN
        pfc_remarks_api.preview_configuration(
            :payor_guid, :plan_guid, :remarks_mode, :custom_remark,
            :audit_user, :summary_cursor, :changes_cursor
        );
    ELSE
        pfc_remarks_api.apply_configuration(
            :payor_guid, :plan_guid, :remarks_mode, :custom_remark,
            :audit_user, :expected_state_hash,
            :summary_cursor, :changes_cursor
        );
    END IF;
END;
"""


def _rows_as_dicts(cursor: Any) -> list[dict[str, Any]]:
    columns = [description[0].lower() for description in cursor.description]
    return [dict(zip(columns, row, strict=True)) for row in cursor.fetchall()]


def _technical_changes(changes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "operation_order": int(change["operation_order"]),
            "operation_code": str(change["operation_code"]),
            "target_identifier": change.get("target_electronic_rec_guid"),
            "field_number": change.get("field_number"),
        }
        for change in changes
    ]


def _validate_response(response: dict[str, Any], model: type[BaseModel]) -> None:
    """Check the public contract and JSON encoding while rollback is still possible."""
    model.model_validate(response).model_dump_json()


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


class _OracleSession:
    """Track acquired cursors without deciding when an operation commits."""

    def __init__(self, connection: Any) -> None:
        self.connection = connection
        self.resources: list[tuple[Any, str]] = []

    def track(self, resource: Any, name: str) -> Any:
        if resource is not None:
            self.resources.append((resource, name))
        return resource

    def cursor(self, name: str) -> Any:
        return self.track(self.connection.cursor(), name)


@contextmanager
def _oracle_operation(
    connection_factory: Callable[[], Any],
    *,
    operation: str,
    connection_name: str,
    unexpected_log: str,
    failure_message: str,
) -> Iterator[_OracleSession]:
    """Share ordinary adapters' error policy and reverse-order resource cleanup."""
    connection = None
    session = None
    try:
        connection = connection_factory()
        session = _OracleSession(connection)
        yield session
    except ApiError:
        if connection is not None:
            _rollback_after_error(connection)
        raise
    except oracledb.DatabaseError as exc:
        if connection is not None:
            _rollback_after_error(connection)
        raise translate_oracle_error(exc, operation) from None
    except DatabaseConfigurationError as exc:
        if connection is not None:
            _rollback_after_error(connection)
        raise ApiError(503, "database_failure", "The database connection is not configured.") from exc
    except Exception as exc:
        if connection is not None:
            _rollback_after_error(connection)
        logger.error(unexpected_log, type(exc).__name__)
        raise ApiError(500, "application_failure", failure_message) from None
    finally:
        if session is not None:
            for resource, name in reversed(session.resources):
                _close_safely(resource, name)
        if connection is not None:
            _close_safely(connection, connection_name)


def _configuration_owners(row: dict[str, Any]) -> list[dict[str, str]]:
    raw = row.get("configuration_owners")
    if raw is None:
        return []
    try:
        owners = json.loads(raw)
        if not isinstance(owners, list) or not owners:
            raise ValueError("Missing owners")
        for owner in owners:
            if not isinstance(owner, dict) or set(owner) != {"target", "level", "identifier"}:
                raise ValueError("Invalid owner shape")
            if owner["level"] not in {"PAYOR_PLAN", "PAYOR", "USER_TEMPLATE", "FORM_TEMPLATE", "BILLING_FORM"}:
                raise ValueError("Invalid owner level")
            if any(not isinstance(value, str) or not value.strip() for value in owner.values()):
                raise ValueError("Invalid owner identifier")
        return owners
    except (ValueError, TypeError):
        raise ApiError(500, "application_failure", "Configuration ownership could not be resolved safely.") from None


class ConfigurationService:
    """Open one connection per call and delegate all configuration logic to Oracle."""

    def overview(self, *, payor_guid: str, plan_guid: str | None) -> dict[str, Any]:
        """Read independent field states; an unresolved field cannot hide the others."""
        lob = self.line_of_business_current(payor_guid=payor_guid)
        if lob["status"] != "DEFINED":
            return {"fields": {field: {"status": "LOB_REQUIRED"} for field in ("39-41", "77", "80", "81")}}
        readers = {
            "39-41": lambda: self.value_codes_current(payor_guid=payor_guid, plan_guid=plan_guid),
            "77": lambda: self.current(payor_guid=payor_guid, plan_guid=plan_guid, field_number="77"),
            "80": lambda: self.remarks_current(payor_guid=payor_guid, plan_guid=plan_guid),
            "81": lambda: self.current(payor_guid=payor_guid, plan_guid=plan_guid, field_number="81"),
        }
        fields = {}
        for field, read in readers.items():
            try:
                fields[field] = {"status": "RESOLVED", "current": read()}
            except ApiError as exc:
                fields[field] = {"status": "UNAVAILABLE", "error": {"category": exc.category, "message": exc.message}}
        return {"fields": fields}

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

    def list_support_payor_contexts(self) -> dict[str, Any]:
        """List selectable synthetic payor/plan pairs without changing Oracle."""

        with _oracle_operation(
            self._connection_factory,
            operation="support payor context catalog",
            connection_name="support context catalog connection",
            unexpected_log="Unexpected context catalog failure (%s)",
            failure_message="The payor context catalog could not be loaded safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("support context catalog cursor")
            cursor.execute(_SUPPORT_PAYOR_CONTEXTS_QUERY)
            rows = _rows_as_dicts(cursor)
            contexts: list[dict[str, str | None]] = []
            for row in rows:
                payor_guid = str(row.get("payor_guid") or "").strip()
                payor_name = str(row.get("payor_name") or "").strip()
                if not payor_guid or not payor_name:
                    raise ApiError(
                        status_code=500,
                        category="application_failure",
                        message="The database returned an invalid payor context catalog.",
                    )
                contexts.append({
                    "payor_guid": payor_guid,
                    "payor_name": payor_name,
                    "payor_id": (
                        str(row["payor_id"]).strip()
                        if row.get("payor_id") is not None else None
                    ),
                    **({"plan_name": row["plan_name"]} if row.get("plan_name") else {}),
                    "plan_guid": (
                        str(row["plan_guid"]).strip()
                        if row.get("plan_guid") is not None else None
                    ),
                })
            plan_numbers: dict[str, int] = {}
            for context in contexts:
                if context["plan_guid"] is not None:
                    owner = context["payor_guid"]
                    plan_numbers[owner] = plan_numbers.get(owner, 0) + 1
                    context.setdefault("plan_name", f"Plan {plan_numbers[owner]}")
            connection.rollback()
            return {"contexts": contexts}

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

    def value_codes_current(
        self, *, payor_guid: str, plan_guid: str | None
    ) -> dict[str, Any]:
        with _oracle_operation(
            self._connection_factory,
            operation="current Value Codes",
            connection_name="Value Codes connection",
            unexpected_log="Unexpected Value Codes current failure (%s)",
            failure_message="Value Codes could not be resolved safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("Value Codes procedure cursor")
            result_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(_VALUE_CODES_CURRENT_BLOCK, payor_guid=payor_guid,
                           plan_guid=plan_guid, result_cursor=result_out)
            result_cursor = session.track(result_out.getvalue(), "Value Codes result cursor")
            rows = _rows_as_dicts(result_cursor)
            if len(rows) != 1 or rows[0].get("configuration_status") != "RESOLVED":
                raise ApiError(409, "current_state_unsupported",
                               "The current Value Codes configuration requires support review.")
            row = rows[0]
            lob = row.get("line_of_business")
            if lob not in {"HOME_HEALTH", "HOSPICE"}:
                raise ApiError(500, "application_failure",
                               "The database returned an invalid Value Codes result.")
            keys = ("cbsa", "fips", "care_location_value_code",
                    "patient_entered_value_code", "covered_days_value_code")
            if any(row.get(key) not in {"Y", "N"} for key in keys):
                raise ApiError(500, "application_failure",
                               "The database returned an invalid Value Codes result.")
            response = {
                "configuration_status": "RESOLVED",
                "line_of_business": lob,
                "is_default": row.get("is_default") == "Y",
                "selections": {key: row[key] == "Y" for key in keys},
                "canonical_status": str(row["canonical_status"]),
                "display_summary": str(row["display_summary"]),
                "pfc_guid": str(row["pfc_guid"]),
                "configuration_owners": _configuration_owners(row),
                "debug": {
                    "billing_form_code": row.get("billing_form_code"),
                    "source_electronic_rec_guid": row.get("source_electronic_rec_guid"),
                    "existing_payor_her_count": int(row.get("existing_payor_her_count", 0)),
                    "existing_payor_hef_count": int(row.get("existing_payor_hef_count", 0)),
                    "state_hash": row.get("state_hash"),
                },
            }
            connection.rollback()
            return response

    def value_codes_preview(self, *, selections: dict[str, bool], **kwargs: Any) -> dict[str, Any]:
        return self._run_value_codes(selections=selections, mode="PREVIEW",
                                     expected_state_hash=None, **kwargs)

    def value_codes_apply(self, *, selections: dict[str, bool],
                          expected_state_hash: str, **kwargs: Any) -> dict[str, Any]:
        return self._run_value_codes(selections=selections, mode="APPLY",
                                     expected_state_hash=expected_state_hash, **kwargs)

    def _run_value_codes(self, *, payor_guid: str, plan_guid: str | None,
                         selections: dict[str, bool], audit_user: str,
                         mode: str, expected_state_hash: str | None) -> dict[str, Any]:
        with _oracle_operation(
            self._connection_factory,
            operation=mode.lower() + " Value Codes",
            connection_name="Value Codes connection",
            unexpected_log="Unexpected Value Codes adapter failure (%s)",
            failure_message="The Value Codes operation failed safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("Value Codes procedure cursor")
            summary_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            changes_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            flags = {key: "Y" if selections[key] else "N" for key in (
                "cbsa", "fips", "care_location_value_code",
                "patient_entered_value_code", "covered_days_value_code")}
            cursor.execute(_VALUE_CODES_CHANGE_BLOCK, payor_guid=payor_guid,
                plan_guid=plan_guid, audit_user=audit_user, operation_mode=mode,
                expected_state_hash=expected_state_hash, summary_cursor=summary_out,
                changes_cursor=changes_out, **flags)
            summary_cursor = session.track(summary_out.getvalue(), "Value Codes summary cursor")
            changes_cursor = session.track(changes_out.getvalue(), "Value Codes changes cursor")
            summaries = _rows_as_dicts(summary_cursor); changes = _rows_as_dicts(changes_cursor)
            if len(summaries) != 1:
                raise ApiError(500, "application_failure", "The database returned an invalid Value Codes result.")
            row = summaries[0]; status = str(row.get("status"))
            allowed = {"PREVIEW", "NO_CHANGE"} if mode == "PREVIEW" else {"APPLIED", "NO_CHANGE"}
            if status not in allowed:
                raise ApiError(500, "application_failure", "The database returned an invalid Value Codes status.")
            change_count = int(row["change_count"])
            response = {
                "status": status, "is_default": not any(selections.values()),
                "selections": selections, "display_summary": str(row["display_label"]),
                "state_hash": str(row["state_hash"]), "change_count": change_count,
                "summary": _safe_summary(status, change_count), "pfc_guid": row.get("pfc_guid"),
                "debug_changes": _technical_changes(changes),
            }
            _validate_response(response, ValueCodesChangeResponse)
            if mode == "APPLY": connection.commit()
            else: connection.rollback()
            return response

    def remarks_current(
        self, *, payor_guid: str, plan_guid: str | None
    ) -> dict[str, Any]:
        with _oracle_operation(
            self._connection_factory,
            operation="current Remarks",
            connection_name="Remarks connection",
            unexpected_log="Unexpected Remarks current failure (%s)",
            failure_message="Remarks could not be resolved safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("Remarks procedure cursor")
            result_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(
                _REMARKS_CURRENT_BLOCK,
                payor_guid=payor_guid,
                plan_guid=plan_guid,
                result_cursor=result_out,
            )
            result_cursor = session.track(result_out.getvalue(), "Remarks result cursor")
            rows = _rows_as_dicts(result_cursor)
            if len(rows) != 1 or rows[0].get("configuration_status") != "RESOLVED":
                raise ApiError(
                    409,
                    "current_state_unsupported",
                    "The current Remarks configuration requires support review.",
                )
            row = rows[0]
            lob = row.get("line_of_business")
            mode = row.get("remarks_mode")
            custom_remark = row.get("custom_remark")
            if lob not in {"HOME_HEALTH", "HOSPICE"} or mode not in {
                "DEFAULT",
                "CUSTOM",
            }:
                raise ApiError(
                    500,
                    "application_failure",
                    "The database returned an invalid Remarks result.",
                )
            if (mode == "DEFAULT" and custom_remark is not None) or (
                mode == "CUSTOM" and not isinstance(custom_remark, str)
            ):
                raise ApiError(
                    500,
                    "application_failure",
                    "The database returned an invalid Remarks result.",
                )
            response = {
                "configuration_status": "RESOLVED",
                "line_of_business": lob,
                "mode": mode,
                "custom_remark": custom_remark,
                "canonical_status": str(row["canonical_status"]),
                "display_summary": str(row["display_summary"]),
                "pfc_guid": str(row["pfc_guid"]),
                "configuration_owners": _configuration_owners(row),
                "debug": {
                    "billing_form_code": row.get("billing_form_code"),
                    "source_electronic_rec_guid": row.get(
                        "source_electronic_rec_guid"
                    ),
                    "target_action": row.get("target_action"),
                    "source_hef_count": int(row.get("source_hef_count", 0)),
                    "existing_payor_her_count": int(
                        row.get("existing_payor_her_count", 0)
                    ),
                    "existing_payor_hef_count": int(
                        row.get("existing_payor_hef_count", 0)
                    ),
                    "state_hash": row.get("state_hash"),
                },
            }
            connection.rollback()
            return response

    def remarks_preview(self, **kwargs: Any) -> dict[str, Any]:
        return self._run_remarks(
            operation_mode="PREVIEW", expected_state_hash=None, **kwargs
        )

    def remarks_apply(
        self, *, expected_state_hash: str, **kwargs: Any
    ) -> dict[str, Any]:
        return self._run_remarks(
            operation_mode="APPLY",
            expected_state_hash=expected_state_hash,
            **kwargs,
        )

    def _run_remarks(
        self,
        *,
        payor_guid: str,
        plan_guid: str | None,
        mode: str,
        custom_remark: str | None,
        audit_user: str,
        operation_mode: str,
        expected_state_hash: str | None,
    ) -> dict[str, Any]:
        with _oracle_operation(
            self._connection_factory,
            operation=operation_mode.lower() + " Remarks",
            connection_name="Remarks connection",
            unexpected_log="Unexpected Remarks adapter failure (%s)",
            failure_message="The Remarks operation failed safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("Remarks procedure cursor")
            summary_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            changes_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(
                _REMARKS_CHANGE_BLOCK,
                payor_guid=payor_guid,
                plan_guid=plan_guid,
                remarks_mode=mode,
                custom_remark=custom_remark,
                audit_user=audit_user,
                operation_mode=operation_mode,
                expected_state_hash=expected_state_hash,
                summary_cursor=summary_out,
                changes_cursor=changes_out,
            )
            summary_cursor = session.track(summary_out.getvalue(), "Remarks summary cursor")
            changes_cursor = session.track(changes_out.getvalue(), "Remarks changes cursor")
            summaries = _rows_as_dicts(summary_cursor)
            changes = _rows_as_dicts(changes_cursor)
            if len(summaries) != 1:
                raise ApiError(
                    500,
                    "application_failure",
                    "The database returned an invalid Remarks result.",
                )
            row = summaries[0]
            status = str(row.get("status"))
            allowed = (
                {"PREVIEW", "NO_CHANGE"}
                if operation_mode == "PREVIEW"
                else {"APPLIED", "NO_CHANGE"}
            )
            if status not in allowed:
                raise ApiError(
                    500,
                    "application_failure",
                    "The database returned an invalid Remarks status.",
                )
            change_count = int(row["change_count"])
            response = {
                "status": status,
                "mode": mode,
                "custom_remark": custom_remark if mode == "CUSTOM" else None,
                "display_summary": "Default" if mode == "DEFAULT" else "Custom remark",
                "state_hash": str(row["state_hash"]),
                "change_count": change_count,
                "summary": _safe_summary(status, change_count),
                "pfc_guid": row.get("pfc_guid"),
                "debug_changes": _technical_changes(changes),
            }
            _validate_response(response, RemarksChangeResponse)
            if operation_mode == "APPLY":
                connection.commit()
            else:
                connection.rollback()
            return response

    def _run_lob_single(
        self,
        *,
        block: str,
        binds: dict[str, Any],
        operation: str,
        commit: bool,
        expected_status: str,
    ) -> dict[str, Any]:
        with _oracle_operation(
            self._connection_factory,
            operation=operation,
            connection_name="LOB connection",
            unexpected_log="Unexpected LOB adapter failure (%s)",
            failure_message="The Line of Business operation failed safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("LOB procedure cursor")
            result_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(block, **binds, result_cursor=result_out)
            result_cursor = session.track(result_out.getvalue(), "LOB result cursor")
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
            response_model = LineOfBusinessSaveResponse if commit else LineOfBusinessCurrentResponse
            _validate_response(response, response_model)
            if commit:
                connection.commit()
            else:
                connection.rollback()
            return response

    def _run_lob_change(
        self,
        *,
        block: str,
        binds: dict[str, Any],
        operation: str,
        commit: bool,
    ) -> dict[str, Any]:
        with _oracle_operation(
            self._connection_factory,
            operation=operation,
            connection_name="LOB connection",
            unexpected_log="Unexpected LOB change adapter failure (%s)",
            failure_message="The Line of Business operation failed safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("LOB procedure cursor")
            summary_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            targets_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(block, **binds, summary_cursor=summary_out, targets_cursor=targets_out)
            summary_cursor = session.track(summary_out.getvalue(), "LOB summary cursor")
            targets_cursor = session.track(targets_out.getvalue(), "LOB target cursor")
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
            _validate_response(response, LineOfBusinessChangeResponse)
            if commit: connection.commit()
            else: connection.rollback()
            return response

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

    def configuration_context(
        self,
        *,
        payor_guid: str,
        plan_guid: str | None,
    ) -> dict[str, Any]:
        """Return the exact PFC and template identifiers selected by Oracle."""

        with _oracle_operation(
            self._connection_factory,
            operation="configuration context",
            connection_name="context connection",
            unexpected_log="Unexpected context adapter failure (%s)",
            failure_message="The configuration context could not be resolved safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("context procedure cursor")
            outputs = {
                "resolved_payor_guid": cursor.var(str, size=36),
                "resolved_plan_guid": cursor.var(str, size=36),
                "pfc_guid": cursor.var(str, size=36),
                "billing_form_code": cursor.var(str, size=50),
                "form_template_guid": cursor.var(str, size=36),
                "user_form_template_guid": cursor.var(str, size=36),
                "form_template_name": cursor.var(str, size=128),
                "user_form_template_name": cursor.var(str, size=128),
            }
            cursor.execute(
                _CONTEXT_BLOCK,
                payor_guid=payor_guid,
                plan_guid=plan_guid,
                **outputs,
            )
            values = {
                name: (str(output.getvalue()).strip() if output.getvalue() is not None else None)
                for name, output in outputs.items()
            }
            if not all(values[name] for name in (
                "resolved_payor_guid", "pfc_guid", "billing_form_code",
            )):
                raise ApiError(
                    status_code=500,
                    category="application_failure",
                    message="The database returned an invalid configuration context.",
                )
            response = {
                "status": "RESOLVED",
                "payor_guid": values["resolved_payor_guid"],
                "plan_guid": values["resolved_plan_guid"],
                "pfc_guid": values["pfc_guid"],
                "billing_form_code": values["billing_form_code"],
                "form_template_guid": values["form_template_guid"],
                "user_form_template_guid": values["user_form_template_guid"],
                "form_template_name": values["form_template_name"],
                "user_form_template_name": values["user_form_template_name"],
            }
            connection.rollback()
            return response

    def current(
        self,
        *,
        payor_guid: str,
        plan_guid: str | None,
        field_number: str,
    ) -> dict[str, Any]:
        with _oracle_operation(
            self._connection_factory,
            operation="current configuration",
            connection_name="current-state connection",
            unexpected_log="Unexpected current-state adapter failure (%s)",
            failure_message="The current configuration could not be resolved safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("current-state procedure cursor")
            result_out = cursor.var(oracledb.DB_TYPE_CURSOR)
            cursor.execute(
                _CURRENT_BLOCK,
                payor_guid=payor_guid,
                plan_guid=plan_guid,
                field_number=field_number,
                result_cursor=result_out,
            )
            result_cursor = session.track(result_out.getvalue(), "current-state result cursor")
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
        with _oracle_operation(
            self._connection_factory,
            operation=mode.lower(),
            connection_name="procedure connection",
            unexpected_log=f"Unexpected {mode.lower()} adapter failure (%s)",
            failure_message="The configuration operation failed safely.",
        ) as session:
            connection = session.connection
            cursor = session.cursor("procedure cursor")
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
            summary_cursor = session.track(summary_out.getvalue(), "summary cursor")
            changes_cursor = session.track(changes_out.getvalue(), "changes cursor")
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
            _validate_response(response, ConfigurationResponse)
            if mode == "APPLY":
                connection.commit()
            else:
                connection.rollback()
            return response

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
            "debug_changes": _technical_changes(changes),
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
            or _OPTION_FIELD_NUMBERS.get(option_code) != requested_field
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
            "configuration_owners": _configuration_owners(row),
            "canonical": None if canonical_value is None else canonical_value == "Y",
        }
