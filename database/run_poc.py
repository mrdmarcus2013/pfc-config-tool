"""Install and test the synthetic Oracle PFC proof-of-concept schema."""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path

import oracledb
from dotenv import load_dotenv


DATABASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = DATABASE_DIR.parent

ACTION_SCRIPTS = {
    "install": [DATABASE_DIR / "install" / "install_all.sql"],
    "prep3": [DATABASE_DIR / "install" / "005_prep_script_3.sql"],
    "install3": [
        DATABASE_DIR / "install" / "004_scripts_1_2.sql",
        DATABASE_DIR / "install" / "005_script_3.sql",
    ],
    "install_lob": [
        DATABASE_DIR / "install" / "003_option_layer.sql",
        DATABASE_DIR / "install" / "005_script_3.sql",
        DATABASE_DIR / "install" / "006_line_of_business.sql",
    ],
    "install_value_codes": [
        DATABASE_DIR / "install" / "005_prep_script_3.sql",
        DATABASE_DIR / "install" / "005_script_3.sql",
        DATABASE_DIR / "install" / "006_line_of_business.sql",
        DATABASE_DIR / "install" / "007_value_codes_discovery.sql",
    ],
    "install_remarks": [
        DATABASE_DIR / "install" / "005_prep_script_3.sql",
        DATABASE_DIR / "install" / "005_script_3.sql",
        DATABASE_DIR / "install" / "006_line_of_business.sql",
        DATABASE_DIR / "install" / "007_value_codes_discovery.sql",
        DATABASE_DIR / "install" / "008_remarks.sql",
    ],
    "test": [DATABASE_DIR / "tests" / "run_all.sql"],
    "test3": [DATABASE_DIR / "tests" / "test_03_apply_option.sql"],
    "reset": [
        DATABASE_DIR / "04_reset_test_data.sql",
        DATABASE_DIR / "install" / "002_seed.sql",
    ],
    "all": [
        DATABASE_DIR / "install" / "install_all.sql",
        DATABASE_DIR / "tests" / "run_all.sql",
    ],
}

PLSQL_START = re.compile(
    r"^(?:DECLARE|BEGIN|CREATE\s+OR\s+REPLACE\s+"
    r"(?:PACKAGE(?:\s+BODY)?|PROCEDURE|FUNCTION))\b",
    re.IGNORECASE,
)


def strip_block_comments(sql_text: str) -> str:
    return re.sub(r"/\*.*?\*/", "", sql_text, flags=re.DOTALL)


def print_dbms_output(cursor: oracledb.Cursor) -> None:
    chunk_size = 100
    lines_var = cursor.arrayvar(str, chunk_size, 32767)
    count_var = cursor.var(int)

    while True:
        count_var.setvalue(0, chunk_size)
        cursor.callproc("dbms_output.get_lines", (lines_var, count_var))
        count = count_var.getvalue()
        for line in lines_var.getvalue()[:count]:
            if line is not None:
                print(line)
        if count < chunk_size:
            break


def execute_script(cursor: oracledb.Cursor, script_path: Path) -> None:
    script_path = script_path.resolve()
    print(f"Running {script_path.relative_to(PROJECT_DIR)}")
    sql_text = strip_block_comments(script_path.read_text(encoding="utf-8"))
    statement_lines: list[str] = []
    in_plsql = False

    for raw_line in sql_text.splitlines():
        line = raw_line.strip()

        if not statement_lines:
            if not line or line.startswith("--"):
                continue

            upper_line = line.upper()
            if upper_line.startswith(("SET ", "WHENEVER ", "SHOW ERRORS")):
                continue
            if upper_line.startswith("PROMPT"):
                message = line[6:].strip()
                if message:
                    print(message)
                continue
            if line.startswith("@@"):
                include_path = script_path.parent / line[2:].strip()
                execute_script(cursor, include_path)
                continue
            if line.startswith("@"):
                include_path = script_path.parent / line[1:].strip()
                execute_script(cursor, include_path)
                continue

            in_plsql = bool(PLSQL_START.match(line))

        if in_plsql and line == "/":
            cursor.execute("\n".join(statement_lines))
            print_dbms_output(cursor)
            statement_lines = []
            in_plsql = False
            continue

        statement_lines.append(raw_line)

        if not in_plsql and line.endswith(";"):
            statement = "\n".join(statement_lines).rstrip()
            cursor.execute(statement[:-1])
            statement_lines = []

    if statement_lines:
        raise RuntimeError(f"Unterminated SQL statement in {script_path}")


def connect() -> oracledb.Connection:
    load_dotenv(PROJECT_DIR / ".env")
    required_keys = (
        "ORACLE_HOST",
        "ORACLE_PORT",
        "ORACLE_SERVICE_NAME",
        "ORACLE_USER",
        "ORACLE_PASSWORD",
    )
    missing_keys = [key for key in required_keys if not os.getenv(key)]
    if missing_keys:
        raise RuntimeError(
            "Missing required .env keys: " + ", ".join(missing_keys)
        )

    dsn = oracledb.makedsn(
        os.environ["ORACLE_HOST"],
        int(os.environ["ORACLE_PORT"]),
        service_name=os.environ["ORACLE_SERVICE_NAME"],
    )
    return oracledb.connect(
        user=os.environ["ORACLE_USER"],
        password=os.environ["ORACLE_PASSWORD"],
        dsn=dsn,
    )


def print_compiler_errors(cursor: oracledb.Cursor) -> None:
    cursor.execute(
        """
        SELECT name, type, line, position, text
        FROM user_errors
        ORDER BY name, type, sequence
        """
    )
    errors = cursor.fetchall()
    if not errors:
        return

    print("Oracle compiler errors:")
    for name, object_type, line, position, message in errors:
        print(f"  {name} ({object_type}) {line}:{position} {message.strip()}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=ACTION_SCRIPTS)
    args = parser.parse_args()

    connection: oracledb.Connection | None = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            cursor.execute("BEGIN DBMS_OUTPUT.ENABLE(NULL); END;")
            for script_path in ACTION_SCRIPTS[args.action]:
                execute_script(cursor, script_path)
        connection.commit()
        print(f"Oracle POC action '{args.action}' completed successfully.")
        return 0
    except Exception as exc:
        if connection is not None:
            connection.rollback()
            try:
                with connection.cursor() as cursor:
                    print_compiler_errors(cursor)
            except Exception:
                pass
        print(f"Oracle POC action failed: {exc}")
        return 1
    finally:
        if connection is not None:
            connection.close()


if __name__ == "__main__":
    raise SystemExit(main())
