"""Oracle connection setup for the FastAPI adapter."""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import oracledb
from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parents[2]


class DatabaseConfigurationError(RuntimeError):
    """Raised when required local Oracle settings are absent or invalid."""


@dataclass(frozen=True, repr=False, slots=True)
class OracleSettings:
    user: str
    password: str
    host: str
    port: int
    service: str


@lru_cache(maxsize=1)
def get_oracle_settings() -> OracleSettings:
    """Load Oracle settings from the existing local environment without logging values."""

    load_dotenv(PROJECT_ROOT / ".env")
    service = os.getenv("ORACLE_SERVICE") or os.getenv("ORACLE_SERVICE_NAME")
    values = {
        "ORACLE_USER": os.getenv("ORACLE_USER"),
        "ORACLE_PASSWORD": os.getenv("ORACLE_PASSWORD"),
        "ORACLE_HOST": os.getenv("ORACLE_HOST"),
        "ORACLE_PORT": os.getenv("ORACLE_PORT"),
        "ORACLE_SERVICE": service,
    }
    missing = [name for name, value in values.items() if not value]
    if missing:
        raise DatabaseConfigurationError(
            "Missing required Oracle settings: " + ", ".join(missing)
        )

    try:
        port = int(values["ORACLE_PORT"] or "")
    except ValueError as exc:
        raise DatabaseConfigurationError("ORACLE_PORT must be an integer.") from exc

    return OracleSettings(
        user=values["ORACLE_USER"] or "",
        password=values["ORACLE_PASSWORD"] or "",
        host=values["ORACLE_HOST"] or "",
        port=port,
        service=values["ORACLE_SERVICE"] or "",
    )


def create_connection() -> oracledb.Connection:
    """Open a python-oracledb Thin connection for one service operation."""

    settings = get_oracle_settings()
    dsn = oracledb.makedsn(
        settings.host,
        settings.port,
        service_name=settings.service,
    )
    return oracledb.connect(
        user=settings.user,
        password=settings.password,
        dsn=dsn,
    )
