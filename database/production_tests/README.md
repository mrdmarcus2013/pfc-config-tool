# Production validation scripts

Read [Production Database Boundary](../../docs/PRODUCTION_DATABASE_BOUNDARY.md)
before editing or running any file in this directory. Every production script
must pass the automated production-boundary check before it is provided to a
database tester.

These files are standalone MatrixCare validation harnesses, not deployment
scripts. They must not depend on PFC Configuration Tool packages, tables,
types, functions, procedures, or views. READ_ONLY scripts perform no DML or
DDL. ROLLBACK_ONLY_APPLY scripts require a fresh dedicated session, reject a
stale Preview hash before DML, verify temporary state, restore the savepoint,
verify restoration, and finish with a full rollback.

Keep real production identifiers only in an unsaved editor buffer. Committed
manual inputs must retain their placeholders.
