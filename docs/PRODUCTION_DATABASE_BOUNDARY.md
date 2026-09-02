# Production Database Boundary

This document is authoritative for every standalone validation script intended
to run against a MatrixCare production database. These requirements are
mandatory, not recommendations.

## MatrixCare production assumptions

Production scripts may assume only known MatrixCare production objects that
have been explicitly validated. Do not assume that any object installed by
this repository exists in MatrixCare production. Successful execution in local
development Oracle does not establish production compatibility.

## Tool-owned objects

Tool-owned storage, packages, types, functions, and procedures are application
implementation details. Examples include `PFC_CONFIG_PAYOR_CONTEXT`,
`PFC_VALUE_CODES`, `PFC_VALUE_CODES_API`, and `PFC_APPLY_OPTION`.

Standalone production validation scripts must NEVER require tool-owned
objects. Tool-owned objects must NEVER be deployed into MatrixCare production
merely to support a validation harness.

## Line of Business

`LINE_OF_BUSINESS` is tool-only metadata. MatrixCare production does not
persist it. A production script that needs LOB to interpret a test must receive
it as an explicit manual input and must never query
`PFC_CONFIG_PAYOR_CONTEXT` or another tool-owned metadata store.

## Production script classes

### A. READ_ONLY

Discovery, current-state inspection, and Preview scripts must:

- be standalone and runnable directly in Toad against MatrixCare production;
- use manual literal or constant inputs;
- have no dependency on repository packages or other tool-owned objects;
- execute no `INSERT`, `UPDATE`, `DELETE`, or `MERGE`;
- execute no `CREATE`, `ALTER`, `DROP`, or `TRUNCATE`;
- execute no `COMMIT`.

### B. ROLLBACK_ONLY_APPLY

A rollback-only APPLY harness must:

- be standalone anonymous PL/SQL with no repository package dependency;
- use an explicit immutable safety token and warn that it requires a dedicated
  session with no unrelated uncommitted work;
- contain no `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, or `COMMIT`;
- establish a `SAVEPOINT` before DML;
- lock and re-resolve current PFC, source, and override state;
- independently rebuild the desired state and exact Preview hash;
- reject a stale hash before any target DML;
- perform temporary DML and verify the exact canonical result;
- `ROLLBACK TO` the savepoint and verify exact restoration;
- issue a final full `ROLLBACK` to release locks; and
- issue a full `ROLLBACK` on every failure path.

## Production identifiers

Production payor, plan, and user identifiers belong only in manual inputs and
must never be committed. `AUDIT_USER` is a `VARCHAR2` audit identity such as
`DANIEL`; it is not necessarily a GUID. Use `PUT_AUDIT_USER_HERE`, unless a
specific future environment is explicitly proven to require GUID formatting.

## PFC resolution

The authoritative PFC resolution rules are:

- `PAYOR_GUID` must match;
- `CPD_END_DATE > SYSDATE`;
- `DEFAULT_MEDIA_TYPE = 'E'`;
- `TYPE_OF_BILL IS NULL`;
- a null requested plan considers only `PFC.PLAN_GUID IS NULL`;
- a populated requested plan considers the exact plan and null-plan fallback;
- newest `CPD_START_DATE` wins and a tied newest date fails safely; and
- `PAYOR_TYPE_GUID` comes from `PAYORS`, not `PFC` or client input.

## Source HER resolution

The authoritative source must be a non-payor HER with `PAYOR_GUID IS NULL`,
`PLAN_GUID IS NULL`, and `TYPE_OF_BILL IS NULL`. Resolve by this hierarchy:

1. matching USER template;
2. matching FORM template;
3. billing-form/null-template source.

Within one level, exact `PAYOR_TYPE_GUID` outranks NULL. A missing or tied best
source blocks. Never clone configuration from another payor.

## Complete cloning

Production validation must model the complete resolved source HER and every
source HEF. Only explicitly managed HEFs may be overlaid. Every unmanaged HEF
must be copied exactly. Never globally normalize `STO_PROC_NAME` and
`HARD_CODED_DATA` pairs; the paired-value rule applies only to managed fields.

## Minimal override

The canonical target action is:

- `NO_CHANGE` when source already supplies the desired behavior and no cleanup
  is needed, or when one canonical override already equals desired state;
- `REMOVE_OVERRIDE` when desired equals source but a payor override exists in
  cleanup scope; and
- `REBUILD_OVERRIDE` when desired differs from source and current payor state
  is absent, stale, duplicated, or noncanonical.

DEFAULT always means the complete authoritative source and must never create a
payor override.

## Preview hash contract

Preview and rollback APPLY must independently calculate the same deterministic
SHA-256 hash from the same request, resolution context, complete source,
complete desired state, complete current cleanup scope, and target action.
APPLY must not invoke application code to obtain or validate the hash and must
reject a mismatch before DML.

## Production review checklist

Before a production script is given to a database tester, verify all items:

- [ ] Read this document and identify the script class.
- [ ] Confirm every referenced database object is a validated MatrixCare
      production object or Oracle built-in.
- [ ] Confirm there are no tool-owned object dependencies or installation
      instructions.
- [ ] Confirm inputs are manual literals/constants with synthetic placeholders
      committed to source control.
- [ ] Confirm PFC and source resolution exactly follow this document.
- [ ] Confirm complete source cloning and managed-only overlays.
- [ ] Confirm minimal-override and DEFAULT behavior.
- [ ] Confirm Preview/APPLY deterministic hash parity where applicable.
- [ ] Confirm the script-specific DML, DDL, transaction, rollback, and failure
      rules for its class.
- [ ] Run the automated production-boundary test and `git diff --check`.
- [ ] Review the file assuming none of the repository's Oracle objects exist.
