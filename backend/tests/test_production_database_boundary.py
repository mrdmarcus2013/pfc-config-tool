from __future__ import annotations

import re
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
PRODUCTION_SCRIPTS = ROOT / "database" / "production_tests"

# This is the repository-owned Oracle object registry. Whenever a new
# tool-owned table, view, type, package, function, or procedure is added, its
# name must be added here before any production harness is reviewed.
# MatrixCare's real PFC table is intentionally not forbidden.
TOOL_OWNED_ORACLE_OBJECTS = {
    "PFC_CONFIG_PAYOR_CONTEXT",
    "PFC_CONFIG_INTERNAL",
    "PFC_OPTION_TYPES",
    "PFC_OPTION_REGISTRY",
    "PFC_VALUE_CODES",
    "PFC_VALUE_CODES_API",
    "PFC_REMARKS",
    "PFC_REMARKS_API",
    "PFC_LINE_OF_BUSINESS",
    "PFC_APPLY_OPTION",
    "PFC_GET_CURRENT_CONFIG",
    "PFC_DISCOVER_FIELD",
    "PFC_RESOLVE_HER_HEF",
    "PFC_OPT_PROVIDER_TAXONOMY_ON",
    "PFC_OPT_PROVIDER_TAXONOMY_OFF",
    "PFC_OPT_SERVICE_FACILITY",
}

READ_ONLY_SCRIPTS = {
    "03_service_facility_preview.sql",
    "05_provider_taxonomy_preview.sql",
    "07_value_codes_readonly.sql",
    "08_value_codes_preview.sql",
    "10_remarks_readonly.sql",
    "11_remarks_preview.sql",
    "13_plan_guid_relationship_readonly.sql",
    "14_claim_config_reference_capture_readonly.sql",
}
ROLLBACK_ONLY_SCRIPTS = {
    "04_service_facility_apply_rollback.sql",
    "06_provider_taxonomy_apply_rollback.sql",
    "09_value_codes_apply_rollback.sql",
    "12_remarks_apply_rollback.sql",
}
READ_ONLY_FORBIDDEN = {
    "INSERT", "UPDATE", "DELETE", "MERGE",
    "CREATE", "ALTER", "DROP", "TRUNCATE", "COMMIT", "SAVEPOINT",
}
ROLLBACK_ONLY_FORBIDDEN = {"CREATE", "ALTER", "DROP", "TRUNCATE", "COMMIT"}


def executable_sql(text: str) -> str:
    """Remove comments and quoted text while preserving executable tokens."""
    output: list[str] = []
    index = 0
    state = "code"
    while index < len(text):
        current = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""
        if state == "code":
            if current == "-" and following == "-":
                state = "line_comment"
                output.extend("  ")
                index += 2
                continue
            if current == "/" and following == "*":
                state = "block_comment"
                output.extend("  ")
                index += 2
                continue
            if current == "'":
                state = "string"
                output.append(" ")
                index += 1
                continue
            if current == '"':
                state = "quoted_identifier"
                output.append(" ")
                index += 1
                continue
            output.append(current)
            index += 1
            continue
        if state == "line_comment":
            if current in "\r\n":
                state = "code"
                output.append(current)
            else:
                output.append(" ")
            index += 1
            continue
        if state == "block_comment":
            if current == "*" and following == "/":
                state = "code"
                output.extend("  ")
                index += 2
            else:
                output.append(current if current in "\r\n" else " ")
                index += 1
            continue
        delimiter = "'" if state == "string" else '"'
        if current == delimiter and following == delimiter:
            output.extend("  ")
            index += 2
        elif current == delimiter:
            state = "code"
            output.append(" ")
            index += 1
        else:
            output.append(current if current in "\r\n" else " ")
            index += 1
    return "".join(output)


def words_found(sql: str, words: set[str]) -> set[str]:
    return {word for word in words if re.search(rf"\b{re.escape(word)}\b", sql, re.I)}


def executable_mutations_found(sql: str, words: set[str]) -> set[str]:
    # PL/SQL collection.DELETE is an in-memory operation, not SQL DELETE DML.
    without_collection_delete = re.sub(r"\.\s*DELETE\b", "", sql, flags=re.I)
    return words_found(without_collection_delete, words)


def section(text: str, start: str, end: str) -> str:
    start_index = text.index(start)
    end_index = text.index(end, start_index) + len(end)
    return text[start_index:end_index]


@pytest.mark.parametrize("path", sorted(PRODUCTION_SCRIPTS.glob("*.sql")))
def test_production_sql_has_no_tool_owned_dependencies_or_substitution_variables(
    path: Path,
) -> None:
    sql = executable_sql(path.read_text(encoding="utf-8"))
    assert not words_found(sql, TOOL_OWNED_ORACLE_OBJECTS), path.name
    assert not re.search(r"&{1,2}[A-Za-z_][A-Za-z0-9_$#]*", sql), path.name


@pytest.mark.parametrize("name", sorted(READ_ONLY_SCRIPTS))
def test_value_codes_read_only_scripts_have_no_executable_mutation(name: str) -> None:
    sql = executable_sql((PRODUCTION_SCRIPTS / name).read_text(encoding="utf-8"))
    assert not executable_mutations_found(sql, READ_ONLY_FORBIDDEN), name
    assert not re.search(r"\b(?:FOR\s+UPDATE|LOCK\s+TABLE)\b", sql, re.I), name


@pytest.mark.parametrize("name", sorted(ROLLBACK_ONLY_SCRIPTS))
def test_value_codes_rollback_apply_has_required_transaction_guards(name: str) -> None:
    sql = executable_sql((PRODUCTION_SCRIPTS / name).read_text(encoding="utf-8"))
    assert not executable_mutations_found(sql, ROLLBACK_ONLY_FORBIDDEN), name
    assert re.search(r"\bSAVEPOINT\b", sql, re.I), name
    assert re.search(r"\bROLLBACK\s+TO\b", sql, re.I), name
    assert re.search(r"\bROLLBACK\s*;", sql, re.I), name


def test_value_codes_preview_and_apply_share_exact_state_and_hash_contract() -> None:
    preview = (PRODUCTION_SCRIPTS / "08_value_codes_preview.sql").read_text(
        encoding="utf-8"
    )
    apply = (PRODUCTION_SCRIPTS / "09_value_codes_apply_rollback.sql").read_text(
        encoding="utf-8"
    )
    shared_sections = (
        ("    PROCEDURE set_hef_value", "    END build_desired_state;"),
        ("    PROCEDURE decide_target_action", "    END decide_target_action;"),
        ("    PROCEDURE add_atom", "    END calculate_preview_state_hash;"),
    )
    for start, end in shared_sections:
        assert section(preview, start, end) == section(apply, start, end)


def test_remarks_preview_and_apply_share_exact_state_and_hash_contract() -> None:
    preview = (PRODUCTION_SCRIPTS / "11_remarks_preview.sql").read_text(
        encoding="utf-8"
    )
    apply = (PRODUCTION_SCRIPTS / "12_remarks_apply_rollback.sql").read_text(
        encoding="utf-8"
    )
    preview_contract = section(
        preview, "    /* HASH CONTRACT START", "    /* HASH CONTRACT END */"
    ).replace("Script 12", "paired script")
    apply_contract = section(
        apply, "    /* HASH CONTRACT START", "    /* HASH CONTRACT END */"
    ).replace("Script 11", "paired script")
    assert preview_contract == apply_contract


@pytest.mark.parametrize(
    ("preview_name", "apply_name"),
    [
        ("03_service_facility_preview.sql", "04_service_facility_apply_rollback.sql"),
        ("05_provider_taxonomy_preview.sql", "06_provider_taxonomy_apply_rollback.sql"),
        ("08_value_codes_preview.sql", "09_value_codes_apply_rollback.sql"),
        ("11_remarks_preview.sql", "12_remarks_apply_rollback.sql"),
    ],
)
def test_preview_and_apply_include_her_mandatory_safety_and_hash_inputs(
    preview_name: str, apply_name: str,
) -> None:
    preview = (PRODUCTION_SCRIPTS / preview_name).read_text(encoding="utf-8")
    apply = (PRODUCTION_SCRIPTS / apply_name).read_text(encoding="utf-8")
    for name, text in ((preview_name, preview), (apply_name, apply)):
        upper = text.upper()
        assert "MANDATORY_IND" in upper, name
        assert "RETURN_1" in upper, name
        assert "DESIRED_HER_MANDATORY_IND" in upper or (
            "OVERLAY_HER.MANDATORY_IND := 'N'" in upper
        ), name
        assert re.search(
            r"MANDATORY_IND.*STO_PROC_NAME|STO_PROC_NAME.*MANDATORY_IND",
            upper,
            re.S,
        ), name
