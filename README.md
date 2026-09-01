# PFC Configuration Tool

PFC Configuration Tool includes a synthetic Oracle proof of concept, a thin
FastAPI backend, and a React/Vite frontend for the first two configurable claim
fields. Oracle is the authoritative configuration engine: the API validates
request shape, manages transactions, invokes stored procedures, and returns
user-safe results. It does not reproduce resolver or comparison logic in Python.

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
- `POST /api/config/current`
- `POST /api/config/preview`
- `POST /api/config/apply`

The API accepts these public option codes:

| Configuration area | Field | Option code | Meaning |
| --- | --- | --- | --- |
| Provider Taxonomy | 81 | `PROVIDER_TAXONOMY_ON` | Enable Provider Taxonomy |
| Provider Taxonomy | 81 | `PROVIDER_TAXONOMY_OFF` | Disable Provider Taxonomy |
| Service Facility | 77 | `SERVICE_FACILITY_ALWAYS_ADDRESS_YES` | Always report the service facility and its address |
| Service Facility | 77 | `SERVICE_FACILITY_ALWAYS_ADDRESS_NO` | Always report the service facility without its address |
| Service Facility | 77 | `SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES` | Report the service facility and address when the care location is not HOME |
| Service Facility | 77 | `SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO` | Report the service facility without its address when the care location is not HOME |
| Service Facility | 77 | `SERVICE_FACILITY_NEVER` | Never report the service facility; address is effectively No |

Clients send exactly one option code per preview or apply request. Service
Facility remains one configuration operation even though Oracle manages its
NM1, N3, and N4 targets atomically. There is no `NEVER` plus address `YES`
configuration.

`POST /api/config/current` accepts `payor_guid`, nullable `plan_guid`, and
`field_number` (`77` or `81`). It performs one read-only Oracle resolution and
returns the effective public option plus a small user-oriented display model.
It does not accept an audit user or client-selected Oracle target. Current-state
reads roll back and never commit; inherited sources and payor overrides are
resolved by Oracle.

Clients must preview a change before applying it. APPLY requires the state hash
returned by PREVIEW for the same configuration context and option. The
application rolls PREVIEW transactions back, commits APPLY only after Oracle
successfully applies and verifies the configuration, and rolls back every
failure. Oracle remains authoritative for resolution, source selection, minimal
overrides, cloning, multi-target atomicity, and state hashing.

Interactive OpenAPI documentation is available at `http://127.0.0.1:8000/docs`
while the server is running.

## Backend Tests

Run mocked unit and API tests without an Oracle connection:

```powershell
python -m pytest backend/tests -q
```

To smoke-test health, option discovery, and read-only Provider Taxonomy and
Service Facility previews against the already installed synthetic Oracle POC,
use:

```powershell
$env:RUN_ORACLE_INTEGRATION='1'
python -m pytest backend/tests/test_oracle_smoke.py -q
Remove-Item Env:RUN_ORACLE_INTEGRATION
```

The smoke test uses only synthetic fixtures and invokes read-only current-state
resolution and `PREVIEW`, so the adapter rolls transactions back and does not
persist a configuration change.
