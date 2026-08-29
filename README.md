# PFC Configuration Tool

PFC Configuration Tool currently includes a synthetic Oracle proof of concept and
a thin FastAPI backend. Oracle is the authoritative configuration engine: the API
validates request shape, manages transactions, invokes the stored procedure, and
returns user-safe results. It does not reproduce resolver or comparison logic in
Python. No frontend is included yet.

## Local Oracle Development

Docker Desktop is required for the local Oracle database. Copy `.env.example` to
`.env`, set `ORACLE_PWD` locally, and then start the database manually:

```powershell
docker compose up -d
```

Oracle listens on `localhost:1521`. The development PDB service is `FREEPDB1`.

The backend reads `ORACLE_USER`, `ORACLE_PASSWORD`, `ORACLE_HOST`, `ORACLE_PORT`,
and `ORACLE_SERVICE` from `.env`. `ORACLE_SERVICE_NAME` remains in the example for
the existing POC runner and is also accepted by the backend as a compatibility
fallback. Never commit `.env`.

## Backend Setup

Create or activate a virtual environment, then install the small dependency set:

```powershell
python -m pip install -r requirements.txt
```

Start the API from the repository root:

```powershell
python -m uvicorn backend.app.main:app --reload
```

The initial API surface is:

- `GET /api/health`
- `GET /api/options`
- `POST /api/config/preview`
- `POST /api/config/apply`

Provider Taxonomy is the only publicly accepted configuration option in this
checkpoint. Service Facility is validated in the database layer but remains
outside the public API until the next integration phase.

Interactive OpenAPI documentation is available at `http://127.0.0.1:8000/docs`
while the server is running.

## Backend Tests

Run mocked unit and API tests without an Oracle connection:

```powershell
python -m pytest backend/tests -q
```

To smoke-test health, option discovery, and a read-only preview against the already
installed synthetic Oracle POC, use:

```powershell
$env:RUN_ORACLE_INTEGRATION='1'
python -m pytest backend/tests/test_oracle_smoke.py -q
Remove-Item Env:RUN_ORACLE_INTEGRATION
```

The smoke test uses only the synthetic `PAYOR_A` fixture and invokes `PREVIEW`, so
the adapter rolls the transaction back and does not persist a configuration change.
