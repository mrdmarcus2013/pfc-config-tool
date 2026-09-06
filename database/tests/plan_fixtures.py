"""Transaction-local plan scenarios, independent of the editable D100 demos.

Only the calling test owns rollback. This helper never commits or changes
existing fixture IDs; E1/E2/E3 collisions abort before any setup DML.
"""

import json
from datetime import datetime
from pathlib import Path

from database.maintenance.rebuild_hierarchy import insert_rows, read_state
from database.maintenance.seed_payor_plans import apply_option, structured_apply

PAYORS = (
    "E1000000-0000-0000-0000-000000000001",
    "E1000000-0000-0000-0000-000000000002",
)


def plan(owner, number):
    return f"E2000000-0000-0000-0000-{owner + 1:06d}{number:06d}"


def pfc(owner, number):
    return f"E3000000-0000-0000-0000-{owner + 1:06d}{number:06d}"


def database_state(cursor):
    """Include trigger-created plan ownership rows in restoration verification."""
    state = read_state(cursor)
    cursor.execute("SELECT * FROM pfc_config_plans")
    columns = [description[0].lower() for description in cursor.description]
    state["PFC_CONFIG_PLANS"] = [dict(zip(columns, row)) for row in cursor]
    return state


def seed(cursor):
    for table, column, prefix in (
        ("payors", "payor_guid", "E1000000-%"),
        ("pfc_config_plans", "plan_guid", "E2000000-%"),
        ("pfc", "pfc_guid", "E3000000-%"),
    ):
        cursor.execute(f"SELECT COUNT(*) FROM {table} WHERE {column} LIKE :prefix", prefix=prefix)
        if cursor.fetchone()[0]:
            raise RuntimeError("Isolated plan test IDs already exist; existing data will not be overwritten.")

    seed_path = Path(__file__).resolve().parents[1] / "maintenance" / "hierarchy_seed.json"
    original = json.loads(seed_path.read_text(encoding="utf-8"))
    for owner, (payor_guid, lob) in enumerate(zip(PAYORS, ("HOME_HEALTH", "HOSPICE"))):
        lob_row = next(
            row for row in original["PFC_CONFIG_PAYOR_CONTEXT"]
            if row["line_of_business"] == lob and any(
                candidate["payor_guid"] == row["payor_guid"]
                and candidate["user_form_template_guid"] is None
                for candidate in original["PFC"]
            )
        )
        payor = next(row for row in original["PAYORS"] if row["payor_guid"] == lob_row["payor_guid"])
        base = next(
            row for row in original["PFC"]
            if row["payor_guid"] == lob_row["payor_guid"] and row["plan_guid"] is None
        )
        insert_rows(cursor, "PAYORS", [{
            **payor,
            "payor_guid": payor_guid,
            "payor_name": f"Synthetic Isolated Plan Test {lob}",
            "payor_id": f"SYN-ISOLATED-PLAN-{owner + 1}",
        }])
        insert_rows(cursor, "PFC_CONFIG_PAYOR_CONTEXT", [{**lob_row, "payor_guid": payor_guid}])
        for number in range(4):
            row = {
                **base,
                "payor_guid": payor_guid,
                "plan_guid": plan(owner, number) if number else None,
                "pfc_guid": pfc(owner, number),
                "rec_ent_date": datetime(2026, 9, 1),
            }
            insert_rows(cursor, "PFC", [row])
            if number:
                cursor.execute(
                    "UPDATE pfc_config_plans SET plan_name=:name WHERE plan_guid=:guid",
                    name=("Inherited Plan", "Custom Plan", "Alternate Plan")[number - 1],
                    guid=plan(owner, number),
                )
            if number == 2:
                insert_rows(cursor, "PFC", [{
                    **row,
                    "pfc_guid": pfc(owner, 99),
                    "rec_ent_date": datetime(2026, 8, 1),
                    "cpd_start_date": datetime(2027, 1, 1),
                }])
        apply_option(cursor, payor_guid, None, "PROVIDER_TAXONOMY_ON")
        apply_option(cursor, payor_guid, plan(owner, 2), "PROVIDER_TAXONOMY_OFF")
        apply_option(cursor, payor_guid, plan(owner, 2), "SERVICE_FACILITY_ALWAYS_ADDRESS_YES")
        apply_option(cursor, payor_guid, plan(owner, 3), "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO")
        structured_apply(cursor, "pfc_remarks_api", [
            payor_guid, plan(owner, 2), "CUSTOM", "Synthetic plan-specific remark",
        ])
        flags = ["Y", "Y", "N", "N", "N"] if owner == 0 else ["N", "N", "N", "Y", "Y"]
        structured_apply(cursor, "pfc_value_codes_api", [payor_guid, plan(owner, 2), *flags])
