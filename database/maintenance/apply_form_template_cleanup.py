"""Apply the approved synthetic local-database preview; default is read-only.

Run from the repository root with python -m database.maintenance.apply_form_template_cleanup.
--rehearse verifies the exact DML and rolls it back. --apply commits it.
The naming catalog is local tool metadata, not a MatrixCare production object.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path

from backend.app.database import create_connection, get_oracle_settings


HERE = Path(__file__).resolve().parent
TABLES = (
    "PAYORS", "PFC", "PFC_CONFIG_PAYOR_CONTEXT", "HCFA_ELECTRONIC_RECORDS",
    "HCFA_ELECTRONIC_FIELDS", "LINKING_FORM_LU",
)
CATALOG = "PFC_CONFIG_FORM_TEMPLATES"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def snapshot(cursor):
    result = {}
    for table in TABLES:
        cursor.execute("SELECT * FROM " + table)
        columns = [d[0].lower() for d in cursor.description]
        result[table] = [dict(zip(columns, row)) for row in cursor]
    return result


def fingerprint(data):
    canonical = json.dumps({
        k: sorted(v, key=lambda r: json.dumps(r, sort_keys=True, default=str))
        for k, v in data.items()
    }, sort_keys=True, default=str)
    return hashlib.sha256(canonical.encode()).hexdigest()


def lock_and_check(cursor, plan):
    for table in TABLES:
        cursor.execute("LOCK TABLE " + table + " IN EXCLUSIVE MODE NOWAIT")
    before = snapshot(cursor)
    require(fingerprint(before) == plan["database_fingerprint"],
            "Database differs from the approved preview; no cleanup was applied.")
    return before


def mutate(cursor, before, plan):
    expected = copy.deepcopy(before)
    cursor.execute("SELECT SYSDATE FROM dual")
    modified_at = cursor.fetchone()[0]
    audit_user = "SYN_TEMPLATE_CLEANUP"
    counts = {"pfc_updated": 0, "her_updated": 0, "her_deleted": 0, "hef_deleted": 0}

    def update(table, key, guid, new):
        cursor.execute(
            "UPDATE " + table + " SET form_template_guid=:template, "
            "rec_mod_date=:modified, rec_mod_user=:audit_identity WHERE " + key + "=:guid",
            template=new, modified=modified_at, audit_identity=audit_user, guid=guid,
        )
        require(cursor.rowcount == 1, "Unexpected update count")
        matches = [r for r in expected[table] if r[key] == guid]
        require(len(matches) == 1, "Unexpected record identity")
        matches[0].update(form_template_guid=new, rec_mod_date=modified_at,
                          rec_mod_user=audit_user)

    for assignment in plan["assignments"]:
        for pfc in assignment["pfc_updates"]:
            if pfc["old_form_template_guid"] != pfc["new_form_template_guid"]:
                update("PFC", "pfc_guid", pfc["pfc_guid"], pfc["new_form_template_guid"])
                counts["pfc_updated"] += 1
    for action in plan["her_actions"]:
        guid = action["electronic_rec_guid"]
        if action["action"] == "DELETE_HER_AND_HEFS":
            cursor.execute("DELETE FROM hcfa_electronic_fields WHERE electronic_rec_guid=:g", g=guid)
            require(cursor.rowcount == action["hef_count"], "Unexpected dependent HEF count")
            counts["hef_deleted"] += cursor.rowcount
            cursor.execute("DELETE FROM hcfa_electronic_records WHERE electronic_rec_guid=:g", g=guid)
            require(cursor.rowcount == 1, "Unexpected HER delete count")
            counts["her_deleted"] += 1
            for table in ("HCFA_ELECTRONIC_FIELDS", "HCFA_ELECTRONIC_RECORDS"):
                expected[table] = [r for r in expected[table] if r["electronic_rec_guid"] != guid]
        else:
            require(action["action"] in ("UPDATE_FORM_REFERENCE", "CLEAR_UNUSED_FORM_REFERENCE"),
                    "Unknown preview action")
            update("HCFA_ELECTRONIC_RECORDS", "electronic_rec_guid", guid,
                   action["new_form_template_guid"])
            counts["her_updated"] += 1
    after = snapshot(cursor)
    require(fingerprint(after) == fingerprint(expected), "Database differs from exact expected changes")
    require(counts == {"pfc_updated": 21, "her_updated": 5, "her_deleted": 5, "hef_deleted": 14},
            "Cleanup counts differ from approval")
    assignments = {r["payor_guid"]: r["form_template_guid"] for r in plan["assignments"]}
    require(len(assignments) == 26, "Expected 26 unique payors")
    for row in after["PFC"]:
        require(row["form_template_guid"] == assignments[row["payor_guid"]], "Wrong PFC assignment")
    templates = {r["form_template_guid"] for r in plan["templates"]}
    for template in templates:
        require(sum(t == template for t in assignments.values()) == 13, "Expected 13 payors per template")
    for table in ("PFC", "HCFA_ELECTRONIC_RECORDS"):
        require(all(r["form_template_guid"] in templates | {None} for r in after[table]),
                "Obsolete form reference remains")
    her_ids = {r["electronic_rec_guid"] for r in after["HCFA_ELECTRONIC_RECORDS"]}
    require(all(r["electronic_rec_guid"] in her_ids for r in after["HCFA_ELECTRONIC_FIELDS"]),
            "Orphan HEF remains")
    return counts, fingerprint(after)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--rehearse", action="store_true")
    mode.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    require(get_oracle_settings().host.lower() in ("localhost", "127.0.0.1", "::1"),
            "This maintenance operation is local-only")
    plan = json.loads((HERE / "form_template_cleanup_preview.json").read_text())
    with create_connection() as connection:
        with connection.cursor() as cursor:
            if not (args.apply or args.rehearse):
                cursor.execute("SET TRANSACTION READ ONLY")
                require(fingerprint(snapshot(cursor)) == plan["database_fingerprint"], "Preview is stale")
                print("Preview matches: 13 Home Health, 13 Hospice; 21 PFC updates, 5 HER updates, 5 HER/14 HEF deletions.")
                return
            before = lock_and_check(cursor, plan)
            if args.apply:
                cursor.execute("SELECT COUNT(*) FROM user_tables WHERE table_name=:t", t=CATALOG)
                if cursor.fetchone()[0] == 0:
                    # Oracle DDL commits: create the empty catalog before any DML,
                    # then reacquire locks and revalidate the original fingerprint.
                    cursor.execute(
                        "CREATE TABLE pfc_config_form_templates ("
                        "form_template_guid VARCHAR2(36) PRIMARY KEY, "
                        "template_name VARCHAR2(128) NOT NULL UNIQUE)"
                    )
                    before = lock_and_check(cursor, plan)
                cursor.execute("LOCK TABLE " + CATALOG + " IN EXCLUSIVE MODE NOWAIT")
                cursor.execute("SELECT COUNT(*) FROM " + CATALOG)
                require(cursor.fetchone()[0] == 0, "Unexpected existing name catalog data")
                for template in plan["templates"]:
                    cursor.execute("INSERT INTO " + CATALOG + " VALUES (:guid, :name)",
                                   guid=template["form_template_guid"], name=template["name"])
            counts, after_hash = mutate(cursor, before, plan)
            if args.rehearse:
                connection.rollback()
                require(fingerprint(snapshot(cursor)) == plan["database_fingerprint"],
                        "Rollback restoration check failed")
                print("Rehearsal verified and rolled back:", json.dumps(counts))
                return
            cursor.execute("SELECT form_template_guid, template_name FROM " + CATALOG)
            require(dict(cursor.fetchall()) == {t["form_template_guid"]: t["name"] for t in plan["templates"]},
                    "Template catalog verification failed")
            connection.commit()
            report = {"status": "APPLIED", "approved_fingerprint": plan["database_fingerprint"],
                      "applied_fingerprint": after_hash, "counts": counts, "templates": plan["templates"],
                      "payors_per_template": 13, "pfc_records_assigned": 27,
                      "orphan_hefs": 0, "obsolete_form_references": 0}
            (HERE / "form_template_cleanup_result.json").write_text(json.dumps(report, indent=2) + "\n")
            print("Committed and verified:", json.dumps(report))


if __name__ == "__main__":
    main()
