# PFC Configuration Tool

Payor and plan dropdowns, plan inheritance, and additive synthetic fixtures are
documented in [Payor plan configuration](docs/PAYOR_PLAN_CONFIGURATION.md).

Standalone production validation is governed by
[`docs/PRODUCTION_DATABASE_BOUNDARY.md`](docs/PRODUCTION_DATABASE_BOUNDARY.md).
Every file under `database/production_tests/` must pass the automated boundary
check before it is given to a database tester; tool-owned Oracle objects must
never be installed in MatrixCare production to support a validation harness.

PFC Configuration Tool includes a synthetic Oracle proof of concept, a thin
FastAPI backend, and a React/Vite frontend for the configurable claim-field
capabilities. Oracle is the authoritative configuration engine: the API validates
request shape, manages transactions, invokes stored procedures, and returns
user-safe results. It does not reproduce resolver or comparison logic in Python.

Generic claim configuration is governed by
[`docs/CLAIM_CONFIGURATION_ENGINE_RULES.md`](docs/CLAIM_CONFIGURATION_ENGINE_RULES.md).
Globally, any desired HER whose stored procedure is not `RETURN_1` must have
`MANDATORY_IND = 'N'`; `RETURN_1` does not force either mandatory value. Default
remains exact inheritance and blocks when the inherited source violates this
safety rule instead of creating a repair override.

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
- `GET /api/support/payor-contexts`
- `POST /api/config/current`
- `POST /api/config/context`
- `POST /api/config/preview`
- `POST /api/config/apply`
- `POST /api/config/line-of-business/current`
- `POST /api/config/line-of-business/save`
- `POST /api/config/line-of-business/preview-change`
- `POST /api/config/line-of-business/apply-change`
- `POST /api/config/value-codes/current`
- `POST /api/config/value-codes/preview`
- `POST /api/config/value-codes/apply`
- `POST /api/config/remarks/current`
- `POST /api/config/remarks/preview`
- `POST /api/config/remarks/apply`

Line of Business is stored once per payor as `HOME_HEALTH` or `HOSPICE`.
Claim-field current, preview, and apply operations are unavailable until the
payor has a saved value. First-time assignment preserves existing overrides.
Changing a saved value requires Preview then Apply and atomically removes every
payor-specific override in the authoritative managed-target registry across all
plans; unregistered configuration targets are not changed.

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

Value Codes (UB-04 fields 39â€“41) uses the separate structured endpoints and
never exposes its internal recipe identifiers. The request contains boolean
capabilities: Home Health supports CBSA and CBSA with FIPS; Hospice supports
care-location 61/G8, patient-entered value, and value code 80/days.
Care-location and patient-entered are mutually exclusive; value code 80/days
is independent, so Hospice has six valid states including Default. No
selections means Default: inherit the complete source resolved by the normal
MatrixCare hierarchy and keep no payor override. FIPS without CBSA, cross-LOB
flags, and conflicting Hospice combinations fail safely.

Remarks (UB-04 field 80) also uses a structured API. `DEFAULT` inherits the
complete authoritative source and keeps no payor override. `CUSTOM` accepts
the user's actual remark, clones the complete source configuration, and
hard-codes the trimmed text in managed field NTE02 while setting the managed
NTE segment values. Existing recognized custom text is read back from Oracle
and repopulates the editor exactly. Blank text is forbidden because it can
cause claim rejection. The current configured maximum is a temporary 100
characters, centralized as `REMARKS_CUSTOM_REMARK_MAX_LENGTH` in the Oracle,
backend, and frontend boundary modules pending confirmation of the production
limit.

`POST /api/config/current` accepts `payor_guid`, nullable `plan_guid`, and
`field_number` (`77` or `81`). It performs one read-only Oracle resolution and
returns the effective public option plus a small user-oriented display model.
It does not accept an audit user or client-selected Oracle target. Current-state
reads roll back and never commit; inherited sources and payor overrides are
resolved by Oracle.

`POST /api/config/context` accepts only `payor_guid` and nullable `plan_guid`.
It uses the same Oracle PFC resolver and returns the selected payor, plan, PFC,
billing form, form-template, and user-form-template identifiers for Tier 2
diagnostics. It is read-only and does not accept audit data.

`GET /api/support/payor-contexts` supplies the Tier 2 selector with eligible
synthetic payor/plan pairs. The local POC endpoint is deliberately restricted
to `SYN-*` payors. Selecting an item still calls the authoritative context
resolver; the client cannot independently choose a PFC or template GUID.
Production payor discovery requires host-authenticated Tier 2 authorization
and is outside this synthetic endpoint's scope.

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
