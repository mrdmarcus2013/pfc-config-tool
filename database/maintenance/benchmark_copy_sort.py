"""Compare the current copy digest sort with its original quadratic sort.

Default previews the benchmark without connecting. --run executes anonymous,
in-memory PL/SQL in a local read-only transaction, then rolls back. The script
changes only its own session's NLS settings; it installs nothing and performs
no configuration DML. Every case verifies ordered bytes and rolling-hash parity.
"""

import argparse
import hashlib
import json
import random
import statistics
from pathlib import Path

import oracledb

from backend.app.database import create_connection, get_oracle_settings


SQL_TEMPLATE = r"""
DECLARE
    TYPE t_strings IS TABLE OF VARCHAR2(32767) INDEX BY PLS_INTEGER;
    l_input t_strings; l_old t_strings; l_new t_strings;
    l_json JSON_ARRAY_T := JSON_ARRAY_T.parse(:input_json);
    l_rounds PLS_INTEGER := :rounds;
    l_started TIMESTAMP WITH TIME ZONE;
    l_old_times JSON_ARRAY_T := JSON_ARRAY_T();
    l_new_times JSON_ARRAY_T := JSON_ARRAY_T();
    l_result JSON_OBJECT_T := JSON_OBJECT_T();
    l_old_hash VARCHAR2(64); l_new_hash VARCHAR2(64);

    FUNCTION digest(p_text VARCHAR2) RETURN VARCHAR2 IS
        l_hash VARCHAR2(64);
    BEGIN
        SELECT RAWTOHEX(STANDARD_HASH(p_text, 'SHA256')) INTO l_hash FROM dual;
        RETURN l_hash;
    END;
    PROCEDURE feed(p_hash IN OUT VARCHAR2, p_text VARCHAR2) IS
    BEGIN
        p_hash := digest(p_hash || ':' || LENGTHB(p_text) || ':' || p_text);
    END;
    FUNCTION elapsed_ms(p_started TIMESTAMP WITH TIME ZONE) RETURN NUMBER IS
        l_diff INTERVAL DAY TO SECOND := SYSTIMESTAMP - p_started;
    BEGIN
        RETURN (EXTRACT(DAY FROM l_diff) * 86400 + EXTRACT(HOUR FROM l_diff) * 3600
            + EXTRACT(MINUTE FROM l_diff) * 60 + EXTRACT(SECOND FROM l_diff)) * 1000;
    END;
    -- Original PFC_COPY digest sort, retained as the independent reference.
    PROCEDURE original_sort(p_values IN OUT NOCOPY t_strings) IS
        l_temp VARCHAR2(32767);
    BEGIN
        IF p_values.COUNT > 1 THEN
            FOR i IN 2..p_values.COUNT LOOP
                FOR j IN REVERSE 2..i LOOP
                    IF p_values(j) < p_values(j-1) THEN
                        l_temp := p_values(j);
                        p_values(j) := p_values(j-1);
                        p_values(j-1) := l_temp;
                    END IF;
                END LOOP;
            END LOOP;
        END IF;
    END;

__CURRENT_SORT__

BEGIN
    IF l_json.get_size() > 0 THEN
        FOR i IN 0..l_json.get_size()-1 LOOP
            l_input(i+1) := l_json.get_string(i);
            IF l_input(i+1) IS NULL THEN
                RAISE_APPLICATION_ERROR(-20990, 'Non-null benchmark input required');
            END IF;
        END LOOP;
    END IF;
    -- Warm up once. Loading/copying inputs and hashing outputs are untimed.
    FOR trial IN 0..l_rounds LOOP
        l_old := l_input;
        l_started := SYSTIMESTAMP;
        original_sort(l_old);
        IF trial > 0 THEN l_old_times.append(elapsed_ms(l_started)); END IF;
        l_new := l_input;
        l_started := SYSTIMESTAMP;
        sort_digests(l_new);
        IF trial > 0 THEN l_new_times.append(elapsed_ms(l_started)); END IF;
    END LOOP;
    l_old_hash := digest('PFC_SORT_PARITY');
    l_new_hash := l_old_hash;
    feed(l_old_hash, TO_CHAR(l_old.COUNT));
    feed(l_new_hash, TO_CHAR(l_new.COUNT));
    IF l_old.COUNT <> l_new.COUNT THEN
        RAISE_APPLICATION_ERROR(-20991, 'Sorted counts differ');
    END IF;
    IF l_old.COUNT > 0 THEN
        FOR i IN 1..l_old.COUNT LOOP
            IF UTL_RAW.CAST_TO_RAW(l_old(i)) <> UTL_RAW.CAST_TO_RAW(l_new(i)) THEN
                RAISE_APPLICATION_ERROR(-20992, 'Ordered bytes differ at position ' || i);
            END IF;
            feed(l_old_hash, l_old(i));
            feed(l_new_hash, l_new(i));
        END LOOP;
    END IF;
    IF l_old_hash <> l_new_hash THEN
        RAISE_APPLICATION_ERROR(-20993, 'Rolling hashes differ');
    END IF;
    l_result.put('count', l_old.COUNT);
    l_result.put('original_samples_ms', l_old_times);
    l_result.put('current_samples_ms', l_new_times);
    l_result.put('ordered_hash', l_old_hash);
    :result := l_result.to_clob();
END;
"""


def benchmark_block():
    """Exercise the helper from the working package, never a second candidate copy."""
    package = Path(__file__).resolve().parents[1] / "packages" / "pfc_copy.pkb"
    source = package.read_text(encoding="utf-8")
    start = source.index("    PROCEDURE sort_digests(")
    ending = "    END sort_digests;"
    end = source.index(ending, start) + len(ending)
    return SQL_TEMPLATE.replace("__CURRENT_SORT__", source[start:end])


def run_case(cursor, block, values, rounds):
    output = cursor.var(oracledb.DB_TYPE_CLOB)
    cursor.execute(block, input_json=json.dumps(values), rounds=rounds, result=output)
    result = json.loads(output.getvalue().read())
    result["original_median_ms"] = round(statistics.median(result["original_samples_ms"]), 3)
    result["current_median_ms"] = round(statistics.median(result["current_samples_ms"]), 3)
    result["exact_order_and_hash_parity"] = True
    return result


def digest_values(size):
    values = [hashlib.sha256(str(index).encode()).hexdigest().upper() for index in range(size)]
    random.Random(7123).shuffle(values)
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Run the local read-only benchmark and session NLS checks")
    parser.add_argument("--rounds", type=int, default=3, help="Timed samples after one warm-up per case")
    parser.add_argument("--max-size", type=int, default=4096, help="Largest synthetic digest array")
    args = parser.parse_args()
    if args.rounds < 1 or args.max_size < 2:
        parser.error("--rounds must be positive and --max-size must be at least 2")
    sizes = sorted({size for size in (0, 1, 2, 31, 128, 1024, args.max_size) if size <= args.max_size})
    print(json.dumps({
        "mode": "RUN" if args.run else "PREVIEW",
        "sizes": sizes,
        "rounds": args.rounds,
        "cases": ["random", "sorted", "reverse", "duplicates", "NLS Unicode stability"],
        "scope": "Anonymous in-memory PL/SQL only; no DDL or configuration DML; session NLS changes and final rollback.",
    }), flush=True)
    if not args.run:
        return
    if get_oracle_settings().host.lower() not in {"localhost", "127.0.0.1", "::1"}:
        raise RuntimeError("Local synthetic database only")

    block = benchmark_block()
    with create_connection() as connection:
        try:
            with connection.cursor() as cursor:
                cursor.execute("SET TRANSACTION READ ONLY")
                cursor.execute("SELECT parameter, value FROM nls_session_parameters WHERE parameter IN ('NLS_COMP', 'NLS_SORT')")
                print(json.dumps({"original_nls": dict(cursor.fetchall())}), flush=True)
                for size in sizes:
                    print(json.dumps({"case": "random_hex", **run_case(cursor, block, digest_values(size), args.rounds)}), flush=True)
                values = sorted(digest_values(args.max_size))
                for label, case in (
                    ("sorted_hex", values),
                    ("reverse_hex", values[::-1]),
                    ("duplicate_hex", [values[index % min(11, len(values))] for index in range(args.max_size)]),
                ):
                    print(json.dumps({"case": label, **run_case(cursor, block, case, args.rounds)}), flush=True)
                # Explicit code points keep this check independent of console encoding.
                unicode_case = ["a", "A", chr(193), chr(225), chr(228), "a", "B", "b",
                                chr(946), chr(20013), "_", "9", "Z", "z", chr(128512)] * 4
                random.Random(12).shuffle(unicode_case)
                for collation in ("BINARY", "BINARY_CI", "BINARY_AI"):
                    cursor.callproc("DBMS_SESSION.SET_NLS", ["NLS_COMP", "'LINGUISTIC'"])
                    cursor.callproc("DBMS_SESSION.SET_NLS", ["NLS_SORT", "'" + collation + "'"])
                    for label, case in (("unicode_stability", unicode_case), ("duplicate_hex", digest_values(67) * 2)):
                        print(json.dumps({"collation": collation, "case": label,
                                          **run_case(cursor, block, case, 1)}), flush=True)
        finally:
            connection.rollback()


if __name__ == "__main__":
    main()
