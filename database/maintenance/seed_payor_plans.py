"""Add isolated synthetic plan fixtures. Default previews; --apply rehearses then commits.

Run from the project root: python -m database.maintenance.seed_payor_plans [--apply].
Existing payors and their configuration are preserved. Existing fixture IDs block
re-seeding so user edits to these fixtures are never overwritten.
"""
import argparse
import json
from datetime import datetime
from pathlib import Path

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.rebuild_hierarchy import insert_rows, procedure_row

PAYORS = ["D1000000-0000-0000-0000-000000000001", "D1000000-0000-0000-0000-000000000002"]

def plan(owner, number):
    return f"D2000000-0000-0000-0000-{owner + 1:06d}{number:06d}"

def change(cursor, payor, plan_guid, option, mode="PREVIEW", state_hash=None):
    with cursor.connection.cursor() as summary, cursor.connection.cursor() as changes:
        cursor.callproc("pfc_apply_option", [payor, plan_guid, option, "SYN_PLAN_TEST", mode, state_hash, summary, changes])
        return dict(zip([d[0].lower() for d in summary.description], summary.fetchone()))

def apply_option(cursor, payor, plan_guid, option):
    preview = change(cursor, payor, plan_guid, option)
    return change(cursor, payor, plan_guid, option, "APPLY", preview["state_hash"])

def structured_apply(cursor, package, args):
    with cursor.connection.cursor() as summary, cursor.connection.cursor() as changes:
        cursor.callproc(package + ".preview_configuration", [*args, "SYN_PLAN_TEST", summary, changes])
        preview = dict(zip([d[0].lower() for d in summary.description], summary.fetchone()))
        cursor.callproc(package + ".apply_configuration", [*args, "SYN_PLAN_TEST", preview["state_hash"], summary, changes])
        return dict(zip([d[0].lower() for d in summary.description], summary.fetchone()))

def seed(cursor):
    original = json.loads((Path(__file__).with_name("hierarchy_seed.json")).read_text())
    for i, payor_guid in enumerate(PAYORS):
        cursor.execute("SELECT COUNT(*) FROM payors WHERE payor_guid=:g", g=payor_guid)
        if cursor.fetchone()[0]:
            raise RuntimeError("Synthetic plan fixtures already exist; no existing data will be overwritten.")
        lob = ["HOME_HEALTH", "HOSPICE"][i]
        lob_row = next(r for r in original["PFC_CONFIG_PAYOR_CONTEXT"] if r["line_of_business"] == lob
                       and any(p["payor_guid"] == r["payor_guid"] and p["user_form_template_guid"] is None for p in original["PFC"]))
        payor = next(r.copy() for r in original["PAYORS"] if r["payor_guid"] == lob_row["payor_guid"])
        base = next(r.copy() for r in original["PFC"] if r["payor_guid"] == lob_row["payor_guid"] and r["plan_guid"] is None)
        payor.update(payor_guid=payor_guid, payor_name=f"Synthetic Plan Demo {'Home Health' if i == 0 else 'Hospice'}", payor_id=f"SYN-PLAN-{i+1}")
        insert_rows(cursor, "PAYORS", [payor])
        insert_rows(cursor, "PFC_CONFIG_PAYOR_CONTEXT", [{**lob_row, "payor_guid": payor_guid}])
        for number in range(4):
            row = {**base, "payor_guid": payor_guid, "plan_guid": plan(i, number) if number else None,
                   "pfc_guid": f"D3000000-0000-0000-0000-{i+1:06d}{number:06d}", "rec_ent_date": datetime(2026, 9, 1)}
            insert_rows(cursor, "PFC", [row])
            if number:
                cursor.execute("UPDATE pfc_config_plans SET plan_name=:n WHERE plan_guid=:g",
                               n=["Inherited Plan", "Custom Plan", "Alternate Plan"][number-1], g=plan(i, number))
            if number == 2:
                insert_rows(cursor, "PFC", [{**row, "pfc_guid": f"D3000000-0000-0000-0000-{i+1:06d}000099",
                                              "rec_ent_date": datetime(2026, 8, 1), "cpd_start_date": datetime(2027, 1, 1)}])
        apply_option(cursor, payor_guid, None, "PROVIDER_TAXONOMY_ON")
        apply_option(cursor, payor_guid, plan(i, 2), "PROVIDER_TAXONOMY_OFF")
        apply_option(cursor, payor_guid, plan(i, 2), "SERVICE_FACILITY_ALWAYS_ADDRESS_YES")
        apply_option(cursor, payor_guid, plan(i, 3), "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO")
        structured_apply(cursor, "pfc_remarks_api", [payor_guid, plan(i, 2), "CUSTOM", "Synthetic plan-specific remark"])
        flags = ["Y", "Y", "N", "N", "N"] if i == 0 else ["N", "N", "N", "Y", "Y"]
        structured_apply(cursor, "pfc_value_codes_api", [payor_guid, plan(i, 2), *flags])

def verify(cursor):
    for i, payor in enumerate(PAYORS):
        for number in range(4):
            selected = plan(i, number) if number else None
            row = procedure_row(cursor, "pfc_get_current_config", [payor, selected, "81"])
            assert row["effective_option_code"] == ("PROVIDER_TAXONOMY_OFF" if number == 2 else "PROVIDER_TAXONOMY_ON")
            assert row["pfc_guid"] == f"D3000000-0000-0000-0000-{i+1:06d}{number:06d}"
            for package in ("pfc_value_codes_api", "pfc_remarks_api"):
                row = procedure_row(cursor, package + ".current_configuration", [payor, selected])
                assert row["configuration_status"] == "RESOLVED", row

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    assert get_oracle_settings().host in {"localhost", "127.0.0.1", "::1"}, "Local synthetic database only"
    print("Preview: add 2 synthetic payors, 6 owned plans, 10 PFCs and independent plan overrides; preserve existing rows.")
    if not args.apply:
        return
    with create_connection() as connection:
        with connection.cursor() as cursor:
            try:
                seed(cursor)
                verify(cursor)
                connection.rollback()
                print("Rollback rehearsal passed.")
                seed(cursor)
                verify(cursor)
                connection.commit()
                print("Synthetic plan fixtures committed and verified.")
            except Exception:
                connection.rollback()
                raise

if __name__ == "__main__":
    main()
