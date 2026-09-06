"""Local synthetic billing-form cleanup. Default verifies preview; --apply commits.

Execute from the repository root using python -m database.maintenance.apply_billing_form_cleanup.
Apply rehearses the exact changes with rollback before committing them atomically.
"""

import argparse
import copy
import json
from datetime import datetime, timezone

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.apply_form_template_cleanup import (
    HERE, fingerprint, lock_and_check, require, snapshot,
)


def check_catalog(cursor, plan):
    cursor.execute("SELECT form_template_guid, template_name FROM pfc_config_form_templates ORDER BY form_template_guid")
    actual = [{"form_template_guid": r[0], "template_name": r[1]} for r in cursor]
    require(actual == plan["template_catalog"], "Template catalog differs from preview")
    cursor.execute("SELECT table_name FROM user_tab_columns WHERE column_name='BILLING_FORM_CODE' ORDER BY table_name")
    require([r[0] for r in cursor] == ["HCFA_ELECTRONIC_RECORDS", "LINKING_FORM_LU", "PFC"],
            "Unexpected billing-form reference table")


def mutate(cursor, before, plan):
    expected = copy.deepcopy(before)
    counts = dict.fromkeys(plan["counts"], 0)
    old, new = plan["old_billing_form_code"], plan["retained_billing_form_code"]
    require((old, new) == ("UB04", "837I_5010"), "Unexpected billing-form codes")
    cursor.execute("SELECT SYSDATE FROM dual")
    modified_at = cursor.fetchone()[0]

    def update(table, key, guid):
        cursor.execute("UPDATE " + table + " SET billing_form_code=:new_code, "
                       "rec_mod_date=:changed_at, rec_mod_user='SYN_BILLING_CLEANUP' "
                       "WHERE " + key + "=:guid AND billing_form_code=:old_code",
                       new_code=new, old_code=old, changed_at=modified_at, guid=guid)
        require(cursor.rowcount == 1, "Unexpected update count")
        matches = [r for r in expected[table] if r[key] == guid]
        require(len(matches) == 1, "Unexpected record identity")
        matches[0].update(billing_form_code=new, rec_mod_date=modified_at,
                          rec_mod_user="SYN_BILLING_CLEANUP")

    for pfc in plan["pfc_updates"]:
        update("PFC", "pfc_guid", pfc["pfc_guid"])
        counts["pfc_updates"] += 1
    for action in plan["her_actions"]:
        guid = action["electronic_rec_guid"]
        if action["action"] == "UPDATE_BILLING_FORM_CODE":
            update("HCFA_ELECTRONIC_RECORDS", "electronic_rec_guid", guid)
            counts["her_updates"] += 1
        else:
            require(action["action"] == "DELETE_DUPLICATE_HER_AND_HEFS", "Unknown action")
            cursor.execute("DELETE FROM hcfa_electronic_fields WHERE electronic_rec_guid=:guid", guid=guid)
            require(cursor.rowcount == action["dependent_hef_count"], "Unexpected HEF count")
            counts["hef_deletions"] += cursor.rowcount
            cursor.execute("DELETE FROM hcfa_electronic_records WHERE electronic_rec_guid=:guid AND billing_form_code=:old_code",
                           guid=guid, old_code=old)
            require(cursor.rowcount == 1, "Unexpected HER count")
            counts["her_deletions"] += 1
            for table in ("HCFA_ELECTRONIC_RECORDS", "HCFA_ELECTRONIC_FIELDS"):
                expected[table] = [r for r in expected[table] if r["electronic_rec_guid"] != guid]
    cursor.execute("UPDATE linking_form_lu SET billing_form_code=:new_code WHERE billing_form_code=:old_code",
                   new_code=new, old_code=old)
    counts["field_mapping_updates"] = cursor.rowcount
    for row in expected["LINKING_FORM_LU"]:
        if row["billing_form_code"] == old:
            row["billing_form_code"] = new
    after = snapshot(cursor)
    require(counts == plan["counts"], "Counts differ from approved preview")
    require(fingerprint(after) == fingerprint(expected), "Changes differ from exact expected state")
    for table in ("PFC", "HCFA_ELECTRONIC_RECORDS", "LINKING_FORM_LU"):
        require({r["billing_form_code"] for r in after[table]} == {new}, "Unexpected billing-form code remains")
    require(len(after["PAYORS"]) == 26 and len(after["PFC"]) == 27, "Payor/PFC count changed")
    for template in plan["template_catalog"]:
        require(len({r["payor_guid"] for r in after["PFC"] if r["form_template_guid"] == template["form_template_guid"]}) == 13,
                "Template assignment split changed")
    her_ids = {r["electronic_rec_guid"] for r in after["HCFA_ELECTRONIC_RECORDS"]}
    require(all(r["electronic_rec_guid"] in her_ids for r in after["HCFA_ELECTRONIC_FIELDS"]), "Orphan HEF found")
    check_catalog(cursor, plan)
    return counts, fingerprint(after)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    require(get_oracle_settings().host.lower() in ("localhost", "127.0.0.1", "::1"), "Local database required")
    plan = json.loads((HERE / "billing_form_cleanup_preview.json").read_text())
    with create_connection() as connection:
        with connection.cursor() as cursor:
            if not args.apply:
                cursor.execute("SET TRANSACTION READ ONLY")
                require(fingerprint(snapshot(cursor)) == plan["database_fingerprint"], "Preview is stale")
                check_catalog(cursor, plan)
                print("Preview matches:", json.dumps(plan["counts"]))
                return
            for rehearsal in (True, False):
                before = lock_and_check(cursor, plan)
                cursor.execute("LOCK TABLE pfc_config_form_templates IN EXCLUSIVE MODE NOWAIT")
                check_catalog(cursor, plan)
                counts, after_hash = mutate(cursor, before, plan)
                if rehearsal:
                    connection.rollback()
                    require(fingerprint(snapshot(cursor)) == plan["database_fingerprint"], "Rollback restoration failed")
                    print("Rehearsal passed; exact original state restored.")
                else:
                    connection.commit()
            report = {"status": "APPLIED", "committed_at_utc": datetime.now(timezone.utc).isoformat(),
                      "approved_fingerprint": plan["database_fingerprint"], "applied_fingerprint": after_hash,
                      "counts": counts, "billing_form_codes": ["837I_5010"], "unique_payors": 26,
                      "pfc_records": 27, "payors_per_form_template": 13, "orphan_hefs": 0}
            (HERE / "billing_form_cleanup_result.json").write_text(json.dumps(report, indent=2) + "\n")
            print("Committed and verified:", json.dumps(report))


if __name__ == "__main__":
    main()
