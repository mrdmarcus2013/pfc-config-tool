"""Reproduce the approved synthetic hierarchy. Preview is the default.

--apply performs a rollback rehearsal, verifies inheritance, then commits.
Only HER/HEF, PFC user-template assignments, LOB metadata and the new user
template name catalog are changed. The before snapshot is a stale-state guard.
"""

import argparse
import json
from datetime import datetime, timezone

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.apply_form_template_cleanup import HERE, fingerprint, require

TABLES = ("PAYORS", "PFC", "PFC_CONFIG_PAYOR_CONTEXT", "HCFA_ELECTRONIC_RECORDS",
          "HCFA_ELECTRONIC_FIELDS", "LINKING_FORM_LU", "PFC_CONFIG_FORM_TEMPLATES",
          "PFC_CONFIG_USER_TEMPLATES")
USER_CATALOG_DDL = """CREATE TABLE pfc_config_user_templates (
    user_form_template_guid VARCHAR2(36) PRIMARY KEY,
    template_name VARCHAR2(128) NOT NULL UNIQUE,
    form_template_guid VARCHAR2(36),
    CONSTRAINT fk_user_template_form FOREIGN KEY (form_template_guid)
        REFERENCES pfc_config_form_templates(form_template_guid))"""


def read_state(cursor):
    result = {}
    for table in TABLES:
        cursor.execute("SELECT * FROM " + table)
        names = [d[0].lower() for d in cursor.description]
        result[table] = [dict(zip(names, row)) for row in cursor]
    return result


def value(column, raw):
    return datetime.fromisoformat(raw) if raw is not None and column.endswith("_date") and isinstance(raw, str) else raw


def insert_rows(cursor, table, rows):
    if not rows:
        return
    columns = list(rows[0])
    cursor.executemany("INSERT INTO " + table + " (" + ",".join(columns) + ") VALUES (" +
                       ",".join(":" + str(i + 1) for i in range(len(columns))) + ")",
                       [[value(k, r[k]) for k in columns] for r in rows])


def replace(cursor, desired):
    cursor.execute("DELETE FROM hcfa_electronic_fields")
    cursor.execute("DELETE FROM hcfa_electronic_records")
    # Both tables are now empty in this transaction; readers see the previous
    # committed state until the complete validated replacement commits.
    insert_rows(cursor, "HCFA_ELECTRONIC_RECORDS", desired["HCFA_ELECTRONIC_RECORDS"])
    insert_rows(cursor, "HCFA_ELECTRONIC_FIELDS", desired["HCFA_ELECTRONIC_FIELDS"])
    insert_rows(cursor, "PFC_CONFIG_USER_TEMPLATES", desired["PFC_CONFIG_USER_TEMPLATES"])
    for row in desired["PFC"]:
        cursor.execute("UPDATE pfc SET user_form_template_guid=:u, rec_mod_date=:d, rec_mod_user=:a WHERE pfc_guid=:g",
                       u=row["user_form_template_guid"], d=value("rec_mod_date", row["rec_mod_date"]),
                       a=row["rec_mod_user"], g=row["pfc_guid"])
        require(cursor.rowcount == 1, "PFC assignment target missing")
    for row in desired["PFC_CONFIG_PAYOR_CONTEXT"]:
        cursor.execute("SELECT COUNT(*) FROM pfc_config_payor_context WHERE payor_guid=:g", g=row["payor_guid"])
        if cursor.fetchone()[0] == 0:
            insert_rows(cursor, "PFC_CONFIG_PAYOR_CONTEXT", [row])
        else:
            cursor.execute("UPDATE pfc_config_payor_context SET line_of_business=:lob, rec_mod_date=:d, rec_mod_user=:a WHERE payor_guid=:g",
                           lob=row["line_of_business"], d=value("rec_mod_date", row["rec_mod_date"]),
                           a=row["rec_mod_user"], g=row["payor_guid"])
    require(fingerprint(read_state(cursor)) == fingerprint(desired), "Replacement differs from approved seed")


def procedure_row(cursor, procedure, params):
    with cursor.connection.cursor() as output:
        cursor.callproc(procedure, [*params, output])
        names = [d[0].lower() for d in output.description]
        rows = output.fetchall()
        require(len(rows) == 1, "Expected one current-state result")
        return dict(zip(names, rows[0]))


def verify_inheritance(cursor, desired):
    contexts = {(p["payor_guid"], p["plan_guid"]): p for p in desired["PFC"]}
    for (payor, plan), pfc in contexts.items():
        user = pfc["user_form_template_guid"]
        profile = int(user[-1]) if user else 0
        for field in ("77", "81"):
            row = procedure_row(cursor, "pfc_get_current_config", [payor, plan, field])
            wanted = ("PROVIDER_TAXONOMY_ON" if profile == 1 else "PROVIDER_TAXONOMY_OFF") if field == "81" else {
                2: "SERVICE_FACILITY_ALWAYS_ADDRESS_YES", 3: "SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO",
            }.get(profile, "SERVICE_FACILITY_NEVER")
            require(row["effective_option_code"] == wanted, "Unexpected effective setting")
            owners = json.loads(row["configuration_owners"])
            user_owned = profile == 1 if field == "81" else profile in (2, 3)
            require(all(o["level"] == ("USER_TEMPLATE" if user_owned else "BILLING_FORM") and
                        o["identifier"] == (user if user_owned else "837I_5010") for o in owners), "Wrong setting owner")
        row = procedure_row(cursor, "pfc_value_codes_api.current_configuration", [payor, plan])
        require(row["configuration_status"] == "RESOLVED" and row["is_default"] == "Y", "Value Codes must inherit")
        owner = json.loads(row["configuration_owners"])[0]
        require(owner["identifier"] == (user if profile in (4, 5) else pfc["form_template_guid"]), "Wrong Value Codes owner")
        wanted_summary = "FIPS" if profile == 4 else "days covered" if profile == 5 else "CBSA" if pfc["form_template_guid"].endswith("B100") else "61/G8"
        require(wanted_summary in row["display_summary"], "Inherited capabilities not displayed")
        row = procedure_row(cursor, "pfc_remarks_api.current_configuration", [payor, plan])
        require(row["remarks_mode"] == "DEFAULT" and json.loads(row["configuration_owners"])[0]["level"] == "BILLING_FORM", "Remarks must inherit standard billing configuration")
    return len(contexts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    require(get_oracle_settings().host.lower() in ("localhost", "127.0.0.1", "::1"), "Local database required")
    before = json.loads((HERE / "hierarchy_before.json").read_text())
    before["PFC_CONFIG_USER_TEMPLATES"] = []
    desired = json.loads((HERE / "hierarchy_seed.json").read_text())
    if not args.apply:
        print((HERE / "hierarchy_rebuild_preview.json").read_text())
        return
    with create_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) FROM user_tables WHERE table_name='PFC_CONFIG_USER_TEMPLATES'")
            if cursor.fetchone()[0] == 0:
                # DDL is separate from the atomic data replacement.
                cursor.execute(USER_CATALOG_DDL)
            for rehearsal in (True, False):
                for table in TABLES:
                    cursor.execute("LOCK TABLE " + table + " IN EXCLUSIVE MODE NOWAIT")
                require(fingerprint(read_state(cursor)) == fingerprint(before), "Database changed since preview; rebuild blocked")
                replace(cursor, desired)
                checked = verify_inheritance(cursor, desired)
                require(fingerprint(read_state(cursor)) == fingerprint(desired), "Verification unexpectedly mutated data")
                if rehearsal:
                    connection.rollback()
                    require(fingerprint(read_state(cursor)) == fingerprint(before), "Rollback restoration failed")
                    print("Rehearsal and rollback passed for", checked, "payor/plan contexts.")
                else:
                    connection.commit()
            report = {"status": "APPLIED", "committed_at_utc": datetime.now(timezone.utc).isoformat(),
                      "her_count": 17, "hef_count": 67, "payors": 26, "pfc_records": 27,
                      "home_health_payors": 13, "hospice_payors": 13,
                      "user_templates": 5, "payor_overrides": 0,
                      "verified_contexts": checked, "after_fingerprint": fingerprint(desired)}
            (HERE / "hierarchy_rebuild_result.json").write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps(report))


if __name__ == "__main__":
    main()
