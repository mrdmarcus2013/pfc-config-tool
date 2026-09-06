"""Capture/compare local synthetic Oracle behavior; every Apply is rolled back.

Run as a module with `capture PATH` before installing a refactor, then `compare
PATH` afterwards. Artifacts belong in .run, not source control. Never installs
objects, commits, or changes existing configuration permanently.
"""
import argparse
import json
from datetime import datetime
from pathlib import Path

import oracledb

from backend.app.database import create_connection, get_oracle_settings
from backend.app.services.configuration import OPTION_FIELDS
from database.maintenance.rebuild_hierarchy import read_state, fingerprint

AUDIT = "SYN_STAGE3_TEST"
SOURCE = "F1000000-0000-0000-0000-000000000001"
SOURCE_PLAN = "F2000000-0000-0000-0000-000000000001"
DESTINATION = "F1000000-0000-0000-0000-000000000002"
HOSPICE = "D1000000-0000-0000-0000-000000000002"


def serial(value):
    if isinstance(value, datetime):
        return value.isoformat()
    raise TypeError(type(value).__name__)


def ordered(value):
    return json.dumps(value, default=serial, sort_keys=True, separators=(",", ":"))


def snapshot(cursor):
    state = read_state(cursor)
    cursor.execute("SELECT * FROM pfc_config_plans")
    columns = [item[0].lower() for item in cursor.description]
    state["PFC_CONFIG_PLANS"] = [dict(zip(columns, row)) for row in cursor]
    return state


def result_rows(cursor):
    columns = [item[0].lower() for item in cursor.description]
    return {
        "columns": columns,
        "types": [str(item[1]) for item in cursor.description],
        "rows": [dict(zip(columns, row)) for row in cursor.fetchall()],
    }


def call(connection, procedure, arguments, outputs=1):
    cursors = [connection.cursor() for _ in range(outputs)]
    try:
        with connection.cursor() as cursor:
            cursor.callproc(procedure, [*arguments, *cursors])
        return [result_rows(cursor) for cursor in cursors]
    finally:
        for cursor in reversed(cursors):
            cursor.close()


def copy(connection, source_plan, destination, mode="PREVIEW", state_hash=None):
    with connection.cursor() as cursor:
        result = cursor.var(oracledb.DB_TYPE_CLOB)
        cursor.callproc("pfc_copy.run_copy", [SOURCE, source_plan, destination,
                       mode, AUDIT, state_hash, result])
        return json.loads(result.getvalue().read())


def capture_error(action):
    try:
        return action()
    except oracledb.DatabaseError as exc:
        detail = exc.args[0]
        # PL/SQL stack line numbers change when routines are extracted.
        return {"error_code": detail.code, "error_message": detail.message.splitlines()[0]}


def normalize_after(before, after, result, started, ended):
    """Keep every business attribute; replace only generated IDs and fresh dates."""
    original_guids = {row["electronic_rec_guid"] for row in before["HCFA_ELECTRONIC_RECORDS"]}
    new_rows = [row for row in after["HCFA_ELECTRONIC_RECORDS"]
                if row["electronic_rec_guid"] not in original_guids]
    children = after["HCFA_ELECTRONIC_FIELDS"]
    audit = {"rec_ent_date", "rec_mod_date"}

    def content(row):
        return {key: value for key, value in row.items()
                if key not in audit | {"electronic_rec_guid"}}

    def signature(row):
        return ordered([content(row), sorted(
            [content(child) for child in children if child["electronic_rec_guid"] == row["electronic_rec_guid"]],
            key=ordered)])

    guid_map = {row["electronic_rec_guid"]: f"NEW_HER_{index}"
                for index, row in enumerate(sorted(new_rows, key=signature))}
    for row in [*new_rows, *(row for row in children if row["electronic_rec_guid"] in guid_map)]:
        assert row["rec_ent_user"] == AUDIT
        assert started <= row["rec_ent_date"] <= ended
        assert row["rec_mod_user"] is None and row["rec_mod_date"] is None

    def replace(value):
        if isinstance(value, dict):
            return {key: replace(item) for key, item in value.items()}
        if isinstance(value, list):
            return [replace(item) for item in value]
        return guid_map.get(value, value) if isinstance(value, str) else value

    normalized = {}
    for table, rows in after.items():
        old_rows = before[table]
        normalized_rows = []
        for row in rows:
            normalized_row = replace(row)
            if row not in old_rows:
                # New HER/HEF insert audit dates and changed PFC modification
                # dates must be actual dates in this operation's Oracle window.
                generated = row.get("electronic_rec_guid") in guid_map
                for column in audit:
                    if row.get(column) is not None and (generated or table == "PFC" and column == "rec_mod_date"):
                        assert started <= row[column] <= ended
                        if table == "PFC":
                            assert row["rec_mod_user"] == AUDIT
                        normalized_row[column] = "OPERATION_DATE"
            normalized_rows.append(normalized_row)
        normalized[table] = sorted(normalized_rows, key=ordered)
    return {"result": replace(result), "state": normalized}


def collect():
    if not __debug__:
        raise RuntimeError("Run without -O: verification requires assertions")
    if get_oracle_settings().host.lower() not in {"localhost", "127.0.0.1", "::1"}:
        raise RuntimeError("Local Oracle only")
    with create_connection() as connection, connection.cursor() as cursor:
        cursor.execute("SELECT COUNT(*) FROM payors WHERE payor_id IS NULL OR payor_id NOT LIKE 'SYN-%'")
        if cursor.fetchone()[0] != 0:
            raise RuntimeError("Synthetic catalog required")
        initial = snapshot(cursor)
        initial_hash = fingerprint(initial)
        cursor.execute("SELECT DISTINCT p.payor_guid,p.plan_guid FROM pfc p JOIN payors o ON o.payor_guid=p.payor_guid ORDER BY p.payor_guid,p.plan_guid NULLS FIRST")
        contexts = cursor.fetchall()
        cursor.execute("SELECT DISTINCT record_type_code FROM hcfa_electronic_records WHERE billing_form_code='837I_5010' ORDER BY record_type_code")
        records = [row[0] for row in cursor]
        report = {"initial_fingerprint": initial_hash, "reads": [], "applies": []}
        options = [option["option_code"] for field in OPTION_FIELDS for option in field["options"]]
        try:
            for payor, plan in contexts:
                operations = [("pfc_resolve_her_hef", [payor, plan, record], 1) for record in records]
                operations += [("pfc_get_current_config", [payor, plan, field], 1) for field in ("77", "81")]
                operations += [(package + ".current_configuration", [payor, plan], 1)
                               for package in ("pfc_remarks_api", "pfc_value_codes_api")]
                operations += [("pfc_apply_option", [payor, plan, option, AUDIT, "PREVIEW", None], 2)
                               for option in options]
                for procedure, args, count in operations:
                    report["reads"].append({"procedure": procedure, "arguments": args,
                        "result": capture_error(lambda: call(connection, procedure, args, count))})
            for plan, destination in [(None, DESTINATION), (SOURCE_PLAN, DESTINATION), (SOURCE_PLAN, SOURCE), (SOURCE_PLAN, HOSPICE)]:
                report["reads"].append({"copy": [plan, destination], "result": capture_error(lambda: copy(connection, plan, destination))})
            assert fingerprint(snapshot(cursor)) == initial_hash, "Read-only checks changed configuration"
            connection.rollback()

            for payor, plan in [(SOURCE, None), (SOURCE, SOURCE_PLAN), (HOSPICE, None)]:
                for option in options:
                    def apply_option():
                        preview = call(connection, "pfc_apply_option", [payor, plan, option, AUDIT, "PREVIEW", None], 2)
                        result = call(connection, "pfc_apply_option", [payor, plan, option, AUDIT, "APPLY", preview[0]["rows"][0]["state_hash"]], 2)
                        return {"preview": preview, "apply": result}
                    capture_apply(connection, cursor, initial, report, [payor, plan, option], apply_option)
                for package, selections in [("pfc_remarks_api", ["DEFAULT", None]),
                                             ("pfc_remarks_api", ["CUSTOM", "Synthetic refactor comparison"]),
                                             ("pfc_value_codes_api", ["N"] * 5),
                                             ("pfc_value_codes_api", ["Y", "Y", "N", "N", "N"] if payor != HOSPICE else ["N", "N", "N", "Y", "Y"])]:
                    def apply_structured():
                        arguments = [payor, plan, *selections, AUDIT]
                        preview = call(connection, package + ".preview_configuration", arguments, 2)
                        result = call(connection, package + ".apply_configuration", [*arguments, preview[0]["rows"][0]["state_hash"]], 2)
                        return {"preview": preview, "apply": result}
                    capture_apply(connection, cursor, initial, report, [payor, plan, package, selections], apply_structured)
            for plan in (None, SOURCE_PLAN):
                def apply_copy():
                    preview = copy(connection, plan, DESTINATION)
                    return {"preview": preview, "apply": copy(connection, plan, DESTINATION, "APPLY", preview["state_hash"])}
                capture_apply(connection, cursor, initial, report, ["copy", plan], apply_copy)
            return report
        finally:
            connection.rollback()
            assert fingerprint(snapshot(cursor)) == initial_hash, "Configuration was not restored"


def capture_apply(connection, cursor, initial, report, identity, action):
    cursor.execute("SELECT SYSDATE FROM dual")
    started = cursor.fetchone()[0]
    try:
        result = capture_error(action)
        cursor.execute("SELECT SYSDATE FROM dual")
        ended = cursor.fetchone()[0]
        report["applies"].append({"case": identity, **normalize_after(initial, snapshot(cursor), result, started, ended)})
    finally:
        connection.rollback()
        assert fingerprint(snapshot(cursor)) == fingerprint(initial), "Apply rollback failed to restore configuration"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("capture", "compare"))
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()
    if args.mode == "capture" and args.artifact.exists():
        raise SystemExit("Refusing to overwrite an existing baseline")
    if args.mode == "capture":
        args.artifact.parent.mkdir(parents=True, exist_ok=True)
    expected = json.loads(args.artifact.read_text(encoding="utf-8")) if args.mode == "compare" else None
    current = json.loads(ordered(collect()))
    if expected is not None:
        assert expected["initial_fingerprint"] == current["initial_fingerprint"], "Starting configuration changed"
        for group in ("reads", "applies"):
            assert len(expected[group]) == len(current[group]), f"{group} case count changed"
            for index, (old, new) in enumerate(zip(expected[group], current[group])):
                assert old == new, f"{group} case {index} differs: {new.get('case', new.get('arguments', new.get('copy')))}"
        print("Baseline and refactor results, hashes, full row contents, and audit rules match.")
    else:
        args.artifact.write_text(json.dumps(current, indent=2, sort_keys=True), encoding="utf-8")
    print(f"{len(current['reads'])} read/preview cases; {len(current['applies'])} rollback-only Apply cases; original state restored.")


if __name__ == "__main__":
    main()
