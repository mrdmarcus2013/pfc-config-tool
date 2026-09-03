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

Remarks validation uses files 10 through 12. Script 10 reports effective
Default, Custom, or Unrecognized state. Script 11 produces a read-only Preview
and deterministic state hash. Script 12 accepts that exact hash and the fixed
`ROLLBACK_ONLY_REMARKS` safety token, verifies a temporary Apply, restores the
savepoint, verifies restoration, and finishes with a full rollback. Remarks
LOB is a manual input because it is tool-only metadata; none of these scripts
depends on tool-owned Oracle objects.
