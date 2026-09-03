# Synthetic Oracle POC database

Production-facing validation is governed by
[`docs/PRODUCTION_DATABASE_BOUNDARY.md`](../docs/PRODUCTION_DATABASE_BOUNDARY.md).
Local tool packages are never prerequisites for standalone MatrixCare
production harnesses.

Generic desired-state behavior is governed by
[`docs/CLAIM_CONFIGURATION_ENGINE_RULES.md`](../docs/CLAIM_CONFIGURATION_ENGINE_RULES.md).
The engine normalizes every explicit non-`RETURN_1` desired HER to
`MANDATORY_IND = 'N'`. It preserves `RETURN_1` mandatory values. Default remains
exact inheritance and blocks an unsafe source rather than creating a repair
override.

This database is deliberately synthetic and exists only to prove PFC, HER, and
HEF resolution and future mutation behavior. It does not reproduce unknown
production DDL, constraints, triggers, or indexes. No production data is used,
and production deployment requires a separate schema review.

Use a fresh, disposable Oracle schema for the first installation. From the
repository root, connect without placing a password in shell history:

```powershell
sqlplus /nolog
```

Then run these commands inside SQL*Plus; `CONNECT` prompts for the password:

```sql
CONNECT your_poc_user@//localhost:1521/FREEPDB1
@database/install/install_all.sql
@database/tests/run_all.sql
```

To remove and recreate only the synthetic seed data while retaining the schema
and compiled PL/SQL, run:

```sql
@database/04_reset_test_data.sql
@database/install/002_seed.sql
@database/tests/run_all.sql
```

The installation exits on SQL errors and explicitly rejects invalid Script 1,
Script 2, option-layer, or supporting package objects.

## Resolution architecture

Script 1 is a diagnostic and development-research helper. Its
`LINKING_FORM_LU` results do not determine what an option changes. Option
definitions explicitly list every manually verified record-type target.
Script 2 resolves the authoritative non-payor source and current state for one
explicit record type. Script 3 consumes explicit option targets and performs a
canonical rebuild; it does not call Script 1.

The option type supports one or more targets. Provider Taxonomy uses one target;
Service Facility uses its three explicit NM1/N3/N4 targets. Script 3 evaluates
each target against its resolved non-payor source, returns a target action, and
uses one state hash and savepoint for atomic multi-target PREVIEW/APPLY.

Canonical payor state contains no override when source plus option overlays is
identical to the source. Otherwise it contains exactly one complete payor HER
and HEF configuration. Cleanup is limited to payor, billing form, and explicit
record type, with HEFs deleted before HERs.

PFC resolution requires the selected payor, a future `CPD_END_DATE`, electronic
default media, and a null type of bill. A null requested plan considers only a
null-plan PFC; a populated requested plan considers that plan and the null-plan
fallback. The newest `CPD_START_DATE` wins, and a tie fails safely.
`PAYOR_TYPE_GUID` is authoritative from `PAYORS`.

Source HERs must be non-payor, null-plan, and null-type-of-bill rows. Within a
template level, an exact payor type beats a generic null type. Source selection
then follows matching user-form template, matching form template, and finally
the null-template billing-form source. Missing or tied best sources fail safely.
PFC template GUIDs select the source; a rebuilt payor HER copies both template
GUIDs exactly from that resolved source and never from another payor.

The minimal-override target actions are `NO_CHANGE`, `REMOVE_OVERRIDE`, and
`REBUILD_OVERRIDE`. Functional desired state is compared with inherited source
state before payor-only metadata is applied. Source-equivalent behavior requires
zero payor HERs. A required override contains one complete HER and its complete
source HEF set, with overlays applied. Cleanup scope is exactly `PAYOR_GUID` plus
`BILLING_FORM_CODE` plus explicit `RECORD_TYPE_CODE`.

A new or rebuilt payor HER uses the selected `PAYOR_GUID`, the authoritative
`PAYORS.PAYOR_TYPE_GUID`, null `CARRY_FORWARD_IND`, and
`INCLUDE_RECORD_DATA_ONCLAIM = 'Y'`. `MAX_CARRY_FORWARD` remains source-derived,
and an existing null `PAYOR_TYPE_GUID` alone is tolerated as canonical.

For a managed HEF, `STO_PROC_NAME` and `HARD_CODED_DATA` are alternative value
mechanisms. Setting a non-null stored procedure clears hard-coded data, and
setting non-null hard-coded data clears the stored procedure. Setting both to
non-null values is invalid. `KEEP`/`KEEP` preserves the source exactly, while a
standalone `CLEAR` clears only its requested attribute. Unmanaged HEFs are not
normalized.

`PFC_CONFIG_PAYOR_CONTEXT` stores the tool-owned Line of Business once per
`PAYOR_GUID`. `PFC_LINE_OF_BUSINESS` owns read, initial save, destructive-change
preview, and atomic reset/apply behavior. Its reset scope is derived from
`PFC_OPTION_REGISTRY.GET_MANAGED_TARGETS`, deduplicated by billing form and
record type, and deliberately has no plan predicate.

## Synthetic frontend demo context

The seed data includes `Synthetic UI Demo Payor` for local frontend development:

- payor: `10000000-0000-0000-0000-00000000D001`
- null plan
- PFC: `20000000-0000-0000-0000-00000000D001`
- billing form: `837I_5010`

Its billing-form-level generic sources inherit Provider Taxonomy OFF and Service
Facility NEVER/OFF. It starts with no payor HER/HEF overrides, so Provider
Taxonomy ON and Service Facility ALWAYS/address-yes produce meaningful rebuild
previews through the existing generic engine. No demo-specific logic exists in
the resolver or apply procedure.

## Production-validated options

Provider Taxonomy explicitly targets `B2000A0030PRV080`. ON uses HER procedure
`RETURN_1` and PRV03 procedure `G_PROVIDER_TAXONOMY_CODE`; OFF uses HER procedure
`RETURN_0`.

Service Facility explicitly targets NM1 `D2310E2500NM1343`, N3
`D2310E2650N3346`, and N4 `D2310E2700N4347`. Its five configurations are:

- ALWAYS/Y: NM1, N3, and N4 use `RETURN_1`.
- ALWAYS/N: NM1 uses `RETURN_1`; N3 and N4 use `RETURN_0`.
- CONDITIONAL/Y: all three use `G_D2310E2500NM1343_COUNT`.
- CONDITIONAL/N: NM1 uses the conditional procedure; N3 and N4 use `RETURN_0`.
- NEVER/N: all three use `RETURN_0`.

Service Facility preview, locking, revalidation, hash calculation, changes, and
verification cover all three targets under one savepoint. The operation is
atomic and Script 3 never commits internally.

`PFC_GET_CURRENT_CONFIG` is the read-only current-state companion for fields 77
and 81. It reuses the final PFC and source resolver for each physical target,
combines inherited behavior with any payor override, and maps only the seven
supported public option states. Mixed Service Facility behavior and unsupported
Provider Taxonomy behavior fail safely instead of being guessed. Hard-coded
effective Provider Taxonomy ON is reported as ON with a noncanonical indicator.
The procedure performs no DML and does not commit.

Provider Taxonomy and Service Facility are the first production-validated
database options. Files 03 through 06 in `database/production_tests` are manual
validation harnesses, not deployment scripts. Preview 03 and 05 are read-only.
Rollback APPLY validation 04 and 06 never commit, always finish with a full
rollback, and must run only in fresh, dedicated Toad sessions containing no
unrelated uncommitted work.

Value Codes targets `D23002310HI286` as one private structured capability for
UB-04 fields 39â€“41. `PFC_VALUE_CODES_API` obtains the saved tool-owned LOB and
accepts only structured Y/N flags; private recipe codes are never advertised.
The generic engine remains authoritative for PFC/source resolution, complete
source cloning, four-field overlays (`HI012`, `HI015`, `HI022`, `HI025`),
minimal overrides, hashes, locking, verification, and transactions. An empty
selection is a source-derived Default and therefore always has zero canonical
payor overrides. The legacy generic Value Codes values are diagnostic fallback
knowledge only: without a complete eligible source, the engine blocks instead
of inventing the remaining production HEFs.

Production validation files 07â€“09 accept LOB manually because it is tool-only
metadata. Script 07 is read-only current discovery. Script 08 independently
performs a standalone read-only Preview, and Script 09 independently
recalculates the same hash before its mandatory-token rollback-only Apply.
Neither script depends on repository-installed tool objects. Script 09 must run
only in a fresh, dedicated Toad session containing no unrelated uncommitted
work.

Remarks targets `D23001900NTE182` for UB-04 field 80. `PFC_REMARKS` is a thin
structured adapter over the generic engine: Default supplies no overlays and
therefore means the complete resolved source, while Custom supplies dynamic
request text and overlays only NTE00, NTE01, and NTE02. The complete source HEF
set is retained, including untouched unmanaged paired values. Recognized
Custom state reads the exact NTE02 `HARD_CODED_DATA` back to the caller.
Blank Custom text is rejected at the authoritative Oracle boundary. The
temporary configured maximum is `PFC_REMARKS.C_CUSTOM_REMARK_MAX_LENGTH` (100),
not a confirmed MatrixCare limit; update the corresponding named backend and
frontend boundary constants if that configured limit changes.

The shared managed-target registry includes Remarks, so a Line of Business
change resets its payor overrides atomically with the other managed targets.
Future fields such as NTE03 can be added as another structured overlay without
changing the generic cloning, comparison, hashing, cleanup, or transaction
engine. Production files 10 through 12 provide standalone current inspection,
read-only Preview, and mandatory-rollback Apply validation respectively. LOB is
manual tool-only context, and none depends on tool-owned Oracle objects.

Accepted validation gap: Service Facility `REBUILD_OVERRIDE` passed in
production before the final generic paired HEF rule. The final paired-rule
rebuild path passed locally, but that final rebuild path could not be rerun in
production. This is an accepted validation gap, not an implementation defect.

If SQL*Plus is not installed, the repository also includes a Python runner that
loads the existing `.env` without printing credentials:

```powershell
python -m pip install -r requirements.txt
python database/run_poc.py all
```

After the initial installation, use `python database/run_poc.py test` to rerun
all already-installed tests without recreating or reseeding the schema, or use
`python database/run_poc.py reset` to reset and reseed the POC data.

## Script 3 incremental workflow

Script 3 is installed and tested without recreating tables or bulk reseeding:

```powershell
python database/run_poc.py prep3
python database/run_poc.py install3
python database/run_poc.py test3
```

`prep3` recompiles the explicit-target option definitions and safely updates
only the known legacy synthetic PAYOR_B fixture when that exact old fixture is
present. `install3` installs `PFC_APPLY_OPTION` and its read-only
`PFC_GET_CURRENT_CONFIG` companion. Neither action recreates
tables or reseeds unrelated scenarios. `test3` runs only the Script 3 tests;
`test` includes them in the complete suite. Every mutation scenario rolls back
so repeated runs start from the same data.

Schemas seeded before the explicit-target reconciliation should be reset and
reseeded before `prep3`; the current synthetic fixtures use the verified
Provider Taxonomy identifiers and include the three Service Facility sources.

Script 3 is proven only against this synthetic schema. Its deterministic SHA256
state hash uses a `VARCHAR2(32767)` serialization suitable for the small POC
dataset, not large production configurations. APPLY intentionally takes a
coarse `FOR UPDATE` lock on the PAYORS row to serialize configuration changes
for one payor. Production DDL, constraints, triggers, indexes, transaction
boundaries, serialization sizing, and lock strategy all require database-team
review before deployment.
