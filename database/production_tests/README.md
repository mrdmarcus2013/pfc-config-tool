# Production validation scripts

Read [Production Database Boundary](../../docs/PRODUCTION_DATABASE_BOUNDARY.md)
before editing or running any file in this directory. Every production script
must pass the automated production-boundary check before it is provided to a
database tester.

Standalone claim-configuration harnesses also reproduce the generic business
rules in [Claim Configuration Engine Rules](../../docs/CLAIM_CONFIGURATION_ENGINE_RULES.md),
including the non-`RETURN_1` HER mandatory invariant and the exact-inheritance
Default exception. They must remain independent of tool-owned packages.

These files are standalone MatrixCare validation harnesses, not deployment
scripts. They must not depend on PFC Configuration Tool packages, tables,
types, functions, procedures, or views. READ_ONLY scripts perform no DML or
DDL. ROLLBACK_ONLY_APPLY scripts require a fresh dedicated session, reject a
stale Preview hash before DML, verify temporary state, restore the savepoint,
verify restoration, and finish with a full rollback.

Keep real production identifiers only in an unsaved editor buffer. Committed
manual inputs must retain their placeholders.

Script 13 is a standalone read-only investigation of `PFC.PLAN_GUID` versus
payor-owned `HCFA_ELECTRONIC_RECORDS.PLAN_GUID`. Leave its optional
`PAYOR_GUID` input null to rank candidate payors and return detail for the top
25, or populate it to return all eligible PFC/HER detail for one payor. The
report gathers evidence for a future Payor Copy design; it does not implement
copy behavior or establish a PLAN_GUID engine rule.

Script 14 captures durable schema and aggregate configuration references for
the four MatrixCare claim-configuration tables. Its first two independent
result sets use standard `ALL_*` dictionary visibility; its third result set
contains aggregate PFC/HER/HEF topology and at most 25 minimized technical
examples. It emits no payor names, notes, hard-coded HEF data, or audit-user
values and implements no copy behavior.

Remarks validation uses files 10 through 12. Script 10 reports effective
Default, Custom, or Unrecognized state. Script 11 produces a read-only Preview
and deterministic state hash. Script 12 accepts that exact hash and the fixed
`ROLLBACK_ONLY_REMARKS` safety token, verifies a temporary Apply, restores the
savepoint, verifies restoration, and finishes with a full rollback. Remarks
LOB is a manual input because it is tool-only metadata; none of these scripts
depends on tool-owned Oracle objects.
