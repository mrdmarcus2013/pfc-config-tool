# PFC Configuration Tool Project Rules

## Claim Configuration Engine Rules

Before modifying generic Oracle configuration logic, option definitions,
current/preview/apply behavior, or production claim-configuration harnesses,
read `docs/CLAIM_CONFIGURATION_ENGINE_RULES.md`. It is the authoritative generic
business-rule document. `docs/PRODUCTION_DATABASE_BOUNDARY.md` remains the
authoritative production-environment boundary.

## MatrixCare Production Boundary

Before creating or modifying anything under `database/production_tests/`, read
`docs/PRODUCTION_DATABASE_BOUNDARY.md`. Production scripts must be standalone
and must never depend on repository-installed PFC tool objects. Never install
tool-owned objects into MatrixCare production to make a validation script pass.

- Never use or commit real patient, payor, claim, or production data.
- All test data must be synthetic.
- Never commit credentials or `.env`.
- Oracle compatibility is required.
- Database-changing operations must support preview-before-confirmation.
- HER and HEF changes must be performed atomically.
- Unexpected or ambiguous database states must fail safely instead of guessing.
- Do not add frameworks or dependencies without demonstrated need.
- Keep the initial implementation simple and data-driven.
- User-facing configuration must use plain-language labels; database procedure names and implementation details stay backend-only.
- Never clone configuration from another payor.
- Do not create application functionality until explicitly requested.
