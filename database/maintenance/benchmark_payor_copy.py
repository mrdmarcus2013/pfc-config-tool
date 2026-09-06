"""Benchmark local synthetic Payor Copy without keeping any fixture or Apply DML.

The default prints scenarios without connecting to Oracle. --run executes them
and writes an ignored .run artifact. Use --baseline to compare full logical
outputs and normalized Apply state after installing a performance refactor.
This script never installs objects or commits.
"""
import argparse
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from statistics import median
from time import perf_counter

import oracledb

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.rebuild_hierarchy import fingerprint, insert_rows
from database.maintenance.verify_oracle_refactor import (
    AUDIT, SOURCE as BASIS_PAYOR, SOURCE_PLAN as BASIS_PLAN,
    normalize_after, ordered, snapshot,
)

ROOT = Path(__file__).resolve().parents[2]
GUID_PREFIX = "B9000000-0000-"
PAYOR_PREFIX = "SYN-BENCH-COPY-"
RECORD_PREFIX = "SYN_BENCH_"
FIXTURE_DATE = datetime(2026, 1, 1)
FIXTURE_END = datetime(2099, 1, 1)


@dataclass(frozen=True)
class Scenario:
    name: str
    records: int
    children: int
    contexts: int
    candidates: int


def guid(kind, owner, index=0):
    return f"{GUID_PREFIX}{kind:04d}-{owner:04d}-{index:012d}"


def scenarios(args):
    shapes = [("small", args.records, args.small_children, 1, 1)]
    shapes += [(f"children-{n}", args.records, n, 1, 1) for n in args.children]
    shapes += [(f"contexts-{n}", args.records, args.small_children, n, 1) for n in args.contexts]
    shapes += [(f"candidates-{n}", args.records, args.small_children, 1, n) for n in args.candidates]
    seen = set()
    result = []
    for name, *dimensions in shapes:
        shape = tuple(dimensions)
        if shape not in seen:
            seen.add(shape)
            result.append(Scenario(name, *dimensions))
    return result


def fixture_audit(row):
    return {**row, "rec_ent_date": FIXTURE_DATE, "rec_ent_user": AUDIT,
            "rec_mod_date": None, "rec_mod_user": None}


def require_fresh_namespace(state):
    for table, rows in state.items():
        for row in rows:
            for value in row.values():
                if isinstance(value, str) and value.startswith((GUID_PREFIX, PAYOR_PREFIX, RECORD_PREFIX)):
                    raise RuntimeError(f"Benchmark namespace already exists in {table}; nothing was changed")


def basis_rows(state):
    payors = [row for row in state["PAYORS"] if row["payor_guid"] == BASIS_PAYOR]
    pfcs = [row for row in state["PFC"] if row["payor_guid"] == BASIS_PAYOR and row["plan_guid"] == BASIS_PLAN]
    if len(payors) != 1 or not pfcs:
        raise RuntimeError("The existing synthetic Copy source and source plan are required")
    newest = max(row["rec_ent_date"] for row in pfcs)
    winners = [row for row in pfcs if row["rec_ent_date"] == newest]
    if len(winners) != 1 or winners[0]["billing_form_code"] != "837I_5010":
        raise RuntimeError("The synthetic Copy source must have one supported newest PFC")
    parents = [row for row in state["HCFA_ELECTRONIC_RECORDS"]
               if row["payor_guid"] is None and row["form_template_guid"] is None
               and row["user_form_template_guid"] is None and row["type_of_bill"] is None
               and row["record_type_code"] == "B2000A0030PRV080"]
    if len(parents) != 1:
        raise RuntimeError("A unique synthetic billing-form Taxonomy record is required as a structural fixture")
    children = [row for row in state["HCFA_ELECTRONIC_FIELDS"]
                if row["electronic_rec_guid"] == parents[0]["electronic_rec_guid"]]
    if not children:
        raise RuntimeError("The synthetic structural fixture requires a complete child row")
    return payors[0], winners[0], parents[0], sorted(children, key=ordered)[0]


def seed(cursor, initial, scenario):
    """Insert only reserved-namespace fixtures using complete existing row shapes."""
    require_fresh_namespace(initial)
    payor_row, pfc_row, her_row, hef_row = basis_rows(initial)
    source, source_plan = guid(1, 0), guid(2, 0, 1)
    destinations = [guid(1, n) for n in range(1, scenario.candidates + 1)]
    for owner, payor in enumerate([source, *destinations]):
        insert_rows(cursor, "PAYORS", [fixture_audit({**payor_row, "payor_guid": payor,
            "payor_id": f"{PAYOR_PREFIX}{owner:04d}", "payor_name": f"Synthetic benchmark payor {owner:04d}"})])
        insert_rows(cursor, "PFC_CONFIG_PAYOR_CONTEXT", [fixture_audit({
            "payor_guid": payor, "line_of_business": "HOME_HEALTH"})])
        plans = [None, source_plan] if owner == 0 else [None, *(guid(2, owner, n) for n in range(1, scenario.contexts))]
        for number, plan in enumerate(plans):
            if plan is not None:
                insert_rows(cursor, "PFC_CONFIG_PLANS", [{"plan_guid": plan, "payor_guid": payor,
                    "plan_name": f"Synthetic benchmark plan {owner:04d}-{number:04d}"}])
            insert_rows(cursor, "PFC", [fixture_audit({**pfc_row, "pfc_guid": guid(3, owner, number),
                "payor_guid": payor, "plan_guid": plan, "type_of_bill": None,
                "default_media_type": "E", "start_date": FIXTURE_DATE, "end_date": FIXTURE_END,
                "cpd_start_date": FIXTURE_DATE, "cpd_end_date": FIXTURE_END,
                "form_template_guid": pfc_row["form_template_guid"] if owner == 0 else None,
                "user_form_template_guid": pfc_row["user_form_template_guid"] if owner == 0 else None})])

    def add_record(owner, record, plan, child_count, variant):
        parent_guid = guid(4, owner, record + (scenario.records if variant == "old-plan" else 0))
        record_code = f"{RECORD_PREFIX}{record:06d}"
        insert_rows(cursor, "HCFA_ELECTRONIC_RECORDS", [fixture_audit({**her_row,
            "electronic_rec_guid": parent_guid, "payor_guid": guid(1, owner), "plan_guid": plan,
            "payor_type_guid": payor_row["payor_type_guid"], "record_type_code": record_code,
            "record_name": f"Synthetic benchmark setting {record:06d}", "record_size": child_count,
            "form_template_guid": None, "user_form_template_guid": None, "type_of_bill": None,
            "sto_proc_name": "RETURN_1", "mandatory_ind": "N", "carry_forward_ind": None,
            "include_record_data_onclaim": "Y"})])
        children = [fixture_audit({**hef_row, "electronic_rec_guid": parent_guid,
            "record_type_code": record_code, "field_number": f"{n:010d}",
            "field_name": f"Synthetic benchmark field {n:06d}", "field_name_desc": f"Synthetic {variant} field {n:06d}",
            "position_from": n, "position_thru": n, "order_num": n % 1000,
            "sto_proc_name": None, "hard_coded_data": f"{variant}-{n:06d}"})
            for n in range(1, child_count + 1)]
        insert_rows(cursor, "HCFA_ELECTRONIC_FIELDS", children)

    for record in range(1, scenario.records + 1):
        add_record(0, record, source_plan if record % 2 else None, scenario.children, "source")
    for owner in range(1, scenario.candidates + 1):
        add_record(owner, 1, None, min(scenario.children, 8), "old-payor")
        if scenario.contexts > 1:
            add_record(owner, 1, guid(2, owner, scenario.contexts - 1), min(scenario.children, 8), "old-plan")
    return source, source_plan, destinations


def copy(cursor, source, plan, destination, mode="PREVIEW", state_hash=None):
    result = cursor.var(oracledb.DB_TYPE_CLOB)
    cursor.callproc("pfc_copy.run_copy", [source, plan, destination, mode, AUDIT, state_hash, result])
    return json.loads(result.getvalue().read())


def timed(action):
    started = perf_counter()
    result = action()
    return result, perf_counter() - started


def oracle_time(cursor):
    cursor.execute("SELECT SYSDATE FROM dual")
    return cursor.fetchone()[0]


def measure(cursor, initial, scenario, repeats):
    source, plan, destinations = seed(cursor, initial, scenario)
    fixture = snapshot(cursor)
    fixture_hash = fingerprint(fixture)
    cursor.execute("SAVEPOINT benchmark_fixture")
    previews, catalog_times, apply_times = [], [], []
    print("  Warming up Copy Preview (untimed)", flush=True)
    primary_preview = copy(cursor, source, plan, destinations[0])
    catalog = applied = None
    for repeat in range(repeats):
        result, elapsed = timed(lambda: copy(cursor, source, plan, destinations[0]))
        previews.append(elapsed)
        assert result == primary_preview, "Repeated Preview changed its warmup result or hash"
        print(f"  Preview {repeat + 1}/{repeats}: {elapsed:.3f}s", flush=True)
        result, elapsed = timed(lambda: [copy(cursor, source, plan, destination) for destination in destinations])
        catalog_times.append(elapsed)
        if catalog is None:
            catalog = result
        else:
            assert result == catalog, "Repeated candidate catalog changed"
        assert catalog[0] == primary_preview
        print(f"  Candidate loop {repeat + 1}/{repeats}: {elapsed:.3f}s ({len(destinations)} candidates)", flush=True)
    assert fingerprint(snapshot(cursor)) == fixture_hash, "Preview changed fixture data"

    for repeat in range(repeats):
        started = oracle_time(cursor)
        try:
            result, elapsed = timed(lambda: copy(cursor, source, plan, destinations[0], "APPLY", primary_preview["state_hash"]))
            ended = oracle_time(cursor)
            apply_times.append(elapsed)
            normalized = normalize_after(fixture, snapshot(cursor), result, started, ended)
            if applied is None:
                applied = normalized
            else:
                assert normalized == applied, "Repeated Apply changed full normalized rows or results"
            print(f"  Apply {repeat + 1}/{repeats}: {elapsed:.3f}s; audit and full state verified", flush=True)
        finally:
            cursor.execute("ROLLBACK TO benchmark_fixture")
            assert fingerprint(snapshot(cursor)) == fixture_hash, "Apply did not restore fixture state"

    return {"scenario": asdict(scenario), "semantic": {"fixture_fingerprint": fixture_hash,
        "preview": primary_preview, "catalog": catalog, "apply": applied},
        "seconds": {"preview": previews, "catalog": catalog_times, "apply": apply_times}}


def collect(cases, repeats):
    if not __debug__:
        raise RuntimeError("Run without -O: benchmark restoration requires assertions")
    if get_oracle_settings().host.lower() not in {"localhost", "127.0.0.1", "::1"}:
        raise RuntimeError("Local Oracle only")
    connection, connection_seconds = timed(create_connection)
    with connection, connection.cursor() as cursor:
        cursor.execute("SELECT COUNT(*) FROM payors WHERE payor_id IS NULL OR payor_id NOT LIKE 'SYN-%'")
        if cursor.fetchone()[0] != 0:
            raise RuntimeError("Synthetic catalog required")
        initial = snapshot(cursor)
        initial_hash = fingerprint(initial)
        require_fresh_namespace(initial)
        results = []
        try:
            for scenario in cases:
                print(f"Scenario {scenario.name}: {scenario.records} source records x {scenario.children} children; "
                      f"{scenario.contexts} contexts per destination; {scenario.candidates} candidates", flush=True)
                try:
                    results.append(measure(cursor, initial, scenario, repeats))
                finally:
                    connection.rollback()
                    assert fingerprint(snapshot(cursor)) == initial_hash, "Scenario did not restore original state"
            return {"version": 1, "initial_fingerprint": initial_hash, "repeats": repeats,
                    "connection_seconds": connection_seconds, "cases": results}
        finally:
            connection.rollback()
            assert fingerprint(snapshot(cursor)) == initial_hash, "Benchmark did not restore original state"


def artifact_path(raw):
    path = Path(raw)
    if not path.is_absolute():
        path = ROOT / path
    path = path.resolve()
    if not path.is_relative_to((ROOT / ".run").resolve()):
        raise ValueError("Benchmark artifacts must be inside the repository's ignored .run directory")
    return path


def compare(expected, actual):
    assert expected["version"] == actual["version"], "Benchmark protocol changed"
    assert expected["initial_fingerprint"] == actual["initial_fingerprint"], "Starting configuration changed"
    assert len(expected["cases"]) == len(actual["cases"]), "Scenario count changed"
    for old, new in zip(expected["cases"], actual["cases"]):
        assert old["scenario"] == new["scenario"], "Scenario dimensions changed"
        assert old["semantic"] == new["semantic"], f"Full result/hash/row parity failed for {new['scenario']['name']}"
        name = new["scenario"]["name"]
        for operation in ("preview", "catalog", "apply"):
            before, after = median(old["seconds"][operation]), median(new["seconds"][operation])
            print(f"{name} {operation}: {before:.3f}s -> {after:.3f}s ({before / after:.2f}x)")


def positive(value):
    number = int(value)
    if not 1 <= number <= 9999:
        raise argparse.ArgumentTypeError("Expected an integer from 1 through 9999")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Execute temporary fixture DML and rollback-only Copy operations")
    parser.add_argument("--children", nargs="+", type=positive, default=[128, 512, 1024])
    parser.add_argument("--records", type=positive, default=1)
    parser.add_argument("--small-children", type=positive, default=8)
    parser.add_argument("--contexts", nargs="+", type=positive, default=[1, 4, 8], help="Total destination PFC contexts, including no-plan")
    parser.add_argument("--candidates", nargs="+", type=positive, default=[1, 8, 16])
    parser.add_argument("--repeats", type=positive, default=3)
    parser.add_argument("--output", type=artifact_path, default=None)
    parser.add_argument("--baseline", type=artifact_path)
    args = parser.parse_args()
    cases = scenarios(args)
    print(json.dumps({"scenarios": [asdict(case) for case in cases], "repeats": args.repeats,
                      "mode": "rollback-only execution" if args.run else "preview; use --run to execute"}, indent=2), flush=True)
    if not args.run:
        return
    if not __debug__:
        raise RuntimeError("Run without -O: benchmark restoration requires assertions")
    output = args.output or artifact_path(f".run/copy-benchmark-{datetime.now():%Y%m%d-%H%M%S}.json")
    if output.exists():
        raise RuntimeError("Refusing to overwrite an existing benchmark artifact")
    expected = json.loads(args.baseline.read_text(encoding="utf-8")) if args.baseline else None
    actual = json.loads(ordered(collect(cases, args.repeats)))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(actual, indent=2, sort_keys=True), encoding="utf-8")
    if expected is not None:
        compare(expected, actual)
        print("Full Preview outputs/hashes and normalized Apply results/rows match the baseline.")
    print(f"Original state restored; artifact: {output}", flush=True)


if __name__ == "__main__":
    main()
