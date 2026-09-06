# Payor Copy implementation

The current contract is [PFC_COPY_RULES.md](PFC_COPY_RULES.md). Earlier separate
screen, template-copy toggle and deferred-plan proposals are superseded.

Implemented components:

- Oracle package `database/packages/pfc_copy`: generic source classification,
  payor/plan flattening, all-current-context template updates, complete replacement,
  deterministic preview, atomic Apply and canonical/effective verification.
- `backend/app/services/payor_copy.py`: strict request/response models and thin
  transaction adapter; `/api/payor-copy/preview` and `/api/payor-copy/apply`.
- `frontend/src/app/payor-copy-panel.tsx`: header-launched side panel, destination
  payor selection, complete replacement preview, explicit acceptance, guarded
  submission and destination refresh.
- `database/maintenance/seed_payor_copy.py`: additive synthetic source/destination
  demos with source and destination plans and historical context coverage.
- `database/tests/test_payor_copy.py`: rollback-only live integration covering
  source isolation, unknown/full child sets, large state, all plan cleanup,
  template clearing, stale hashes, mismatches, safety and forced failure rollback.
- Backend and frontend tests cover transaction boundaries, API validation,
  preview/acceptance presentation and exact request forwarding.

Ordinary field-editing resolution and minimal overrides retain their existing
semantics. Source copying is confined to this explicitly approved workflow.
Production adaptation, new payor/PFC creation, bulk destination selection and
narrower concurrency locks are outside this implementation.
