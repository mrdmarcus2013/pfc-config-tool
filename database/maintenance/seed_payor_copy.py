"""Add isolated copy demos. Preview by default; --apply rehearses and commits."""
import argparse
import json
from datetime import datetime
from pathlib import Path

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.rebuild_hierarchy import insert_rows
from database.maintenance.seed_payor_plans import apply_option, structured_apply

SOURCE = "F1000000-0000-0000-0000-000000000001"
DESTINATION = "F1000000-0000-0000-0000-000000000002"
SOURCE_PLAN = "F2000000-0000-0000-0000-000000000001"
DESTINATION_PLANS = ["F2000000-0000-0000-0000-000000000002", "F2000000-0000-0000-0000-000000000003"]
HISTORICAL_PFC = "F3000000-0000-0000-0000-000000000099"


def extra_record(cursor, payor, plan, guid, record):
    cursor.execute("SELECT * FROM hcfa_electronic_records WHERE payor_guid IS NULL AND form_template_guid IS NULL AND user_form_template_guid IS NULL AND record_type_code='B2000A0030PRV080'")
    names = [d[0].lower() for d in cursor.description]
    rows = cursor.fetchall()
    assert len(rows) == 1
    source = dict(zip(names, rows[0]))
    cursor.execute("SELECT payor_type_guid FROM payors WHERE payor_guid=:p", p=payor)
    new = {**source, "electronic_rec_guid": guid, "record_type_code": record,
           "payor_guid": payor, "plan_guid": plan, "payor_type_guid": cursor.fetchone()[0],
           "record_name": "Synthetic additional claim setting", "rec_ent_user": "SYN_COPY_SEED"}
    insert_rows(cursor, "HCFA_ELECTRONIC_RECORDS", [new])
    cursor.execute("SELECT * FROM hcfa_electronic_fields WHERE electronic_rec_guid=:g", g=source["electronic_rec_guid"])
    names = [d[0].lower() for d in cursor.description]
    children = [{**dict(zip(names, r)), "electronic_rec_guid": guid, "record_type_code": record} for r in cursor.fetchall()]
    insert_rows(cursor, "HCFA_ELECTRONIC_FIELDS", children)


def seed(cursor):
    data = json.loads(Path(__file__).with_name("hierarchy_seed.json").read_text())
    base_lob = next(r for r in data["PFC_CONFIG_PAYOR_CONTEXT"] if r["line_of_business"] == "HOME_HEALTH"
        and any(p["payor_guid"] == r["payor_guid"] and p["plan_guid"] is None and p["user_form_template_guid"] is None for p in data["PFC"]))
    base_payor = next(r for r in data["PAYORS"] if r["payor_guid"] == base_lob["payor_guid"])
    base_pfc = next(r for r in data["PFC"] if r["payor_guid"] == base_lob["payor_guid"] and r["plan_guid"] is None)
    user_template = next(r["user_form_template_guid"] for r in data["PFC_CONFIG_USER_TEMPLATES"] if r["form_template_guid"] is None)
    for i, payor in enumerate([SOURCE, DESTINATION]):
        cursor.execute("SELECT COUNT(*) FROM payors WHERE payor_guid=:p", p=payor)
        if cursor.fetchone()[0]: raise RuntimeError("Copy demo already exists; existing settings will not be replaced.")
        insert_rows(cursor, "PAYORS", [{**base_payor, "payor_guid": payor,
            "payor_name": "Synthetic Copy Demo " + ["Source", "Destination"][i], "payor_id": "SYN-COPY-DEMO-" + str(i+1)}])
        insert_rows(cursor, "PFC_CONFIG_PAYOR_CONTEXT", [{**base_lob, "payor_guid": payor}])
        for number, plan in enumerate([None, SOURCE_PLAN] if i == 0 else [None, *DESTINATION_PLANS]):
            row = {**base_pfc, "pfc_guid": f"F3000000-0000-0000-0000-{i+1:06d}{number:06d}",
                   "payor_guid": payor, "plan_guid": plan, "rec_ent_date": datetime(2026,9,1),
                   "user_form_template_guid": user_template if i else None}
            insert_rows(cursor, "PFC", [row])
            if plan:
                cursor.execute("UPDATE pfc_config_plans SET plan_name=:n WHERE plan_guid=:p",
                               n="Working Source Plan" if i == 0 else f"Destination Plan {number}", p=plan)
            if i == 1 and number == 1:
                insert_rows(cursor,"PFC",[{**row,"pfc_guid":HISTORICAL_PFC,"rec_ent_date":datetime(2026,8,1)}])
    apply_option(cursor, SOURCE, None, "PROVIDER_TAXONOMY_ON")
    apply_option(cursor, SOURCE, SOURCE_PLAN, "PROVIDER_TAXONOMY_OFF")
    apply_option(cursor, SOURCE, SOURCE_PLAN, "SERVICE_FACILITY_ALWAYS_ADDRESS_YES")
    structured_apply(cursor, "pfc_remarks_api", [SOURCE, None, "CUSTOM", "Synthetic source payor remark"])
    structured_apply(cursor, "pfc_value_codes_api", [SOURCE, SOURCE_PLAN, "Y", "Y", "N", "N", "N"])
    for p in DESTINATION_PLANS:
        apply_option(cursor, DESTINATION, p, "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO")
    structured_apply(cursor, "pfc_remarks_api", [DESTINATION, None, "CUSTOM", "Synthetic old destination remark"])
    extra_record(cursor,SOURCE,SOURCE_PLAN,"F4000000-0000-0000-0000-000000000001","SYN_COPY_UNKNOWN")
    extra_record(cursor,DESTINATION,None,"F4000000-0000-0000-0000-000000000002","SYN_COPY_EXTRA")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply",action="store_true")
    args=parser.parse_args()
    assert get_oracle_settings().host in {"localhost","127.0.0.1","::1"}
    print("Preview: add two isolated synthetic copy payors, three plans, six PFCs and complete known/unknown settings. Existing payors are preserved.")
    if not args.apply: return
    with create_connection() as c:
        with c.cursor() as q:
            try:
                seed(q); c.rollback(); print("Rollback rehearsal passed.")
                seed(q); c.commit(); print("Copy demos committed.")
            except Exception:
                c.rollback(); raise

if __name__ == "__main__": main()
