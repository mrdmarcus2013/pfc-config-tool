# PFC Copy Implementation Plan

**Status:** Active implementation plan  
**Product:** PFC Copy (Payor Format Configuration Copy)  
**Repository:** `pfc-config-tool`  
**Authoritative rules:** `PFC_COPY_RULES.md`, `CLAIM_CONFIGURATION_CANONICAL_RULES.md`  
**Existing Payor Configuration rules:** `CLAIM_CONFIGURATION_ENGINE_RULES.md`

## 1. Purpose

This document tracks how PFC Copy will be implemented in the existing repository.
It is a working implementation plan, not a second source of business rules.
When this plan conflicts with an approved rules document, the rules document wins
and this plan must be updated.

PFC Copy is a separate tool from the Payor Configuration Tool. It may reuse safe
technical patterns and infrastructure, but it must not be implemented as another
Payor Configuration recipe or by changing the meaning of the existing generic
Payor Configuration resolver.

## 2. Current state

### Complete

- Payor Configuration is implemented and working for the current initial catalog.
- PFC Copy product terminology and tool boundaries are documented.
- PFC Copy is explicitly generic and may copy current, future, and unknown record
  types when they otherwise qualify.
- The configuration hierarchy is defined as:

  ```text
  PAYOR > USER TEMPLATE > FORM TEMPLATE > BILLING FORM CODE
  ```

- Copy modes are defined:
  - without templates: replace PAYOR level only;
  - with templates: replace PAYOR plus USER/FORM template levels while retaining
    the BILLING FORM CODE baseline.
- Empty source configuration inside a replacement level clears that destination
  level.
- HER + complete HEF children are one copy unit.
- Copied HER post-selection normalization is defined:
  - `RETURN_1` preserves the source `MANDATORY_IND`;
  - non-`RETURN_1`, including NULL, writes `MANDATORY_IND = 'N'`;
  - `CARRY_FORWARD_IND = NULL`;
  - `INCLUDE_RECORD_DATA_ONCLAIM = 'Y'`.
- PFC Copy and Payor Configuration may overwrite each other's rows when those
  rows are in the later operation's scope.
- Preview-before-Apply, stale-state protection, atomicity, and full verification
  are required.

### Next

Build the non-`PLAN_GUID` PFC Copy foundation using synthetic local Oracle data,
starting with read-only classification and Preview behavior before any persistent
copy DML is introduced.

### Deferred

Final `PLAN_GUID` semantics are intentionally deferred. Do not finalize or infer:

- plan-specific source eligibility/fallback;
- destination plan normalization;
- shared NULL-plan behavior;
- plan-specific destructive scope; or
- behavior for multiple PFC rows sharing plan context.

No working Payor Configuration plan behavior is to be refactored as part of the
initial PFC Copy work.

## 3. Implementation principles

1. **Additive architecture.** Add PFC Copy components beside the existing Payor
   Configuration implementation. Do not convert PFC Copy into a Payor
   Configuration option or recipe.
2. **Oracle remains authoritative.** PFC/HER/HEF classification, desired-state
   construction, state hashing, locking, mutation, and verification belong in
   Oracle. Python is a thin transaction/API adapter.
3. **Replacement, not merge.** Destination rows inside the approved replacement
   scope are not preserved merely because their functional content matches the
   source.
4. **Complete units.** Every selected HER is handled with every HEF child.
5. **Generic record types.** No whitelist based on the current Payor
   Configuration catalog.
6. **Fail closed.** Missing, ambiguous, stale, unsafe, or unsupported state blocks
   the operation rather than being guessed.
7. **No production dependency for normal development.** Initial implementation
   and validation use deterministic synthetic Oracle fixtures. Production access
   is reserved for genuinely unknown MatrixCare facts.
8. **Preserve existing work.** Existing Payor Configuration code and unrelated
   uncommitted production-research files are not reset, rewritten, or cleaned up
   as part of PFC Copy work.

## 4. Repository architecture direction

The current repository already provides reusable patterns:

- `backend/app/database.py` — Oracle connection creation.
- `backend/app/errors.py` — user-safe Oracle error translation.
- `backend/app/services/configuration.py` — connection/cursor lifecycle and
  Preview rollback / Apply commit / failure rollback patterns.
- `database/procedures/03_pfc_apply_option.sql` — savepoint, lock, re-read,
  deterministic state hash, mutation, and verification patterns.
- `frontend/src/api/client.ts` — API error/request wrapper.
- `frontend/src/app/workflow.ts` — Preview invalidation and Apply gating patterns.
- local synthetic schema/reset/install/test runners under `database/`.

PFC Copy should reuse those patterns without making the existing generic Payor
Configuration engine responsible for copy semantics.

### Expected new Oracle area

Preferred direction:

```text
database/packages/pfc_copy.pks
database/packages/pfc_copy.pkb
```

The package should ultimately own three conceptual operations:

```text
LIST_ELIGIBLE_PFCS
PREVIEW_COPY
APPLY_COPY
```

Names may change during implementation, but the responsibilities should remain
separate from `PFC_APPLY_OPTION` and the Payor Configuration option registry.

### Expected new backend area

Preferred direction:

```text
backend/app/services/pfc_copy.py
```

with PFC Copy-specific request/response models kept separate enough that generic
Payor Configuration models do not become a mixed product contract.

Expected API family:

```text
GET/POST /api/pfc-copy/... eligible PFC discovery
POST     /api/pfc-copy/preview
POST     /api/pfc-copy/apply
```

The exact discovery endpoint shape will be finalized when the first backend
slice is implemented.

### Expected new frontend area

Preferred direction:

```text
frontend/src/pfc-copy/
```

The PFC Copy user flow should be a separate screen/workflow from the current
claim-field Payor Configuration UI. It should not be represented as another
field editor.

Initial flow:

```text
Select source payor
  -> select exact eligible source PFC
Select destination payor
  -> select exact eligible destination PFC
Choose Copy template associations: Yes / No
Preview
Review replacement
Apply
```

## 5. Phase 1 — synthetic topology and read-only classifier

**Goal:** Prove that Oracle can classify source/destination configuration by the
approved hierarchy without mutating anything.

### 5.1 Add dedicated PFC Copy fixtures

Prefer a dedicated fixture namespace instead of retrofitting all existing Payor
Configuration cases. Fixtures must use `837I_5010` and synthetic identifiers.

Minimum non-plan fixture families:

1. source and destination with different PAYOR-level configurations;
2. source with zero PAYOR-level HERs and destination with PAYOR-level HERs;
3. source/destination with the same functional PAYOR-level record to prove
   replacement remains replacement;
4. unknown `RECORD_TYPE_CODE` with complete HEF children;
5. source HER containing unmanaged HEFs;
6. `RETURN_1` + `MANDATORY_IND = 'Y'`;
7. `RETURN_1` + `MANDATORY_IND = 'N'`;
8. non-`RETURN_1` source with an inconsistent mandatory value so Preview proves
   destination normalization to `N`;
9. destination PFC using different USER TEMPLATE from source;
10. source USER TEMPLATE HER with both user and form template GUIDs populated;
11. source FORM TEMPLATE HER;
12. billing-form-only HER proving it remains baseline and is not copied as a
    template-level unit;
13. stale/nonapplicable template association;
14. populated `TYPE_OF_BILL` diagnostic row;
15. template GUID shared by more than one synthetic PFC.

`PLAN_GUID` should be NULL in the first fixture family unless a test is
explicitly documenting that plan behavior is deferred. This keeps Phase 1 from
accidentally establishing plan semantics.

### 5.2 Read-only classifier output

The first Oracle implementation should be able to report, for an exact selected
PFC:

- PFC eligibility and identity;
- HER hierarchy level: PAYOR / USER TEMPLATE / FORM TEMPLATE / BILLING FORM;
- whether the row is applicable to the selected PFC;
- whether `TYPE_OF_BILL` makes it diagnostic/nonstandard;
- complete HEF count and child detail;
- whether the row is inside the chosen copy mode's replacement/source scope;
- intended copied-HER normalized values where applicable; and
- explicit reason for every excluded/diagnostic row.

No DML is allowed in this phase.

### 5.3 Phase 1 acceptance gate

Phase 1 passes only when automated local tests prove:

- hierarchy classification is deterministic;
- PAYOR level outranks template columns for classification;
- USER TEMPLATE outranks FORM TEMPLATE when both template GUIDs are populated;
- unknown record types remain eligible data;
- complete HEF sets are discovered without hard-coded child counts;
- empty source is represented as a real replacement result, not `NO_CHANGE`;
- billing-form baseline is not placed in template replacement scope; and
- no current Payor Configuration tests regress.

## 6. Design gate — physical template-level replacement

Before template-level Apply DML is implemented, resolve the physical mutation
strategy for shared template HER rows.

The approved product result is already defined: with templates, the destination
must adopt the source PFC's template associations and must no longer use the old
destination template configuration that was replaced. However, the local schema
shows template HERs as non-payor rows keyed by template GUIDs; those rows can be
shared by multiple PFCs. Blindly deleting a destination's old template HER can
therefore alter another PFC that still references the same template.

The implementation must prove a safe physical strategy that satisfies the
approved effective result without globally deleting a still-shared template row.
Candidate strategies are to be evaluated from the actual schema and synthetic
shared-template fixtures; this plan does not preselect one.

This is an implementation design gate, not a change to the approved copy-mode
business rule.

## 7. Phase 2 — Oracle Preview

**Goal:** Build a complete deterministic intended destination state without
persisting changes.

Preview should accept at minimum:

```text
source_payor_guid
source_pfc_guid
destination_payor_guid
destination_pfc_guid
copy_template_associations
```

An audit user may be included if required to make Preview and Apply contracts
consistent, but Preview itself performs no persistent audit DML.

Preview must:

1. validate exact source/destination PFC eligibility;
2. classify source rows using Phase 1 rules;
3. read destination rows in the replacement scope;
4. build the complete desired post-copy state in memory;
5. normalize only selected copied HER rows;
6. include every HEF child for every copied HER;
7. represent empty source levels as destination removals;
8. include the destination PFC template change when copy-templates is enabled;
9. produce deterministic change diagnostics/counts;
10. compute a deterministic state hash covering all source and destination state
    that can change the result; and
11. return `BLOCKED`, `NO_CHANGE` only where semantically appropriate, or a
    replacement Preview.

Because PFC Copy is replacement rather than merge, a functionally identical
source/destination configuration can still produce replacement actions.

## 8. Phase 3 — backend Preview API

**Goal:** Expose Oracle Preview through a thin PFC Copy-specific service.

Backend responsibilities:

- validate request shape;
- acquire one Oracle connection per operation;
- invoke the Oracle PFC Copy package;
- translate Oracle errors through the established safe error model;
- roll Preview transactions back;
- return a user-oriented response plus optional technical diagnostics;
- do not reproduce hierarchy or comparison logic in Python.

Add unit/API tests using mocks before requiring Oracle integration.

## 9. Phase 4 — frontend Preview workflow

**Goal:** Provide the separate PFC Copy UI through Preview only.

Initial frontend requirements:

- separate PFC Copy screen, not part of the field editor;
- source payor selection;
- source eligible-PFC selection;
- destination payor selection;
- destination eligible-PFC selection;
- Copy template associations checkbox/toggle;
- clear explanation of destructive replacement scope;
- Preview button;
- Preview invalidated whenever source, destination, PFC, or template-copy choice
  changes;
- review showing what destination configuration will be removed/replaced/copied;
- Apply disabled until a current valid Preview exists.

The first frontend slice may use synthetic/demo selection data if payor lookup is
not yet wired, provided the API contracts are real and no demo-specific logic is
placed in Oracle.

## 10. Phase 5 — Apply

**Goal:** Implement atomic destructive replacement after Preview is proven.

Apply must follow the proven safety pattern:

```text
savepoint
  -> lock relevant source/destination/PFC state
  -> re-read
  -> rebuild desired state
  -> recompute hash
  -> reject stale Preview before target DML
  -> delete destination HEFs before parent HERs where replacement requires it
  -> update destination template association if requested
  -> insert new destination HERs
  -> insert every HEF child with the new parent GUID
  -> verify complete resulting state
  -> return success
application commits only after Oracle success
```

Any failure rolls back the entire operation. A template-only partial result or
partially copied HER/HEF set is forbidden.

### Apply ownership/audit rules

For newly inserted destination-owned HERs:

- new `ELECTRONIC_REC_GUID`;
- destination `PAYOR_GUID` for PAYOR-level copied rows;
- destination authoritative `PAYOR_TYPE_GUID` where applicable;
- final `PLAN_GUID` handling remains deferred until approved;
- `CARRY_FORWARD_IND = NULL`;
- `INCLUDE_RECORD_DATA_ONCLAIM = 'Y'`;
- insert audit user/date from the operation;
- modification audit fields NULL.

Every cloned HEF receives the new parent GUID and new insert audit metadata with
cleared modification audit metadata.

## 11. Phase 6 — integration and regression coverage

PFC Copy testing must include both direct copy behavior and interaction with
Payor Configuration.

Required non-plan regression examples:

1. Payor Configuration creates a known setting -> PFC Copy replaces the full
   destination PAYOR configuration -> copied state wins.
2. PFC Copy creates a known setting -> Payor Configuration changes that one
   setting -> Payor Configuration result wins for that setting.
3. PFC Copy includes an unknown record type and complete HEF children.
4. Copy without templates preserves destination template associations and
   template-level effective configuration.
5. Copy with templates changes destination template associations and replaces
   the old effective template configuration safely.
6. Empty source PAYOR level clears destination PAYOR level.
7. Empty source template level clears/replaces the destination template level
   according to the safe physical template strategy.
8. Stale Preview rejects Apply before target DML.
9. A forced failure after some attempted DML restores the original destination
   state completely.
10. Existing Payor Configuration Oracle/backend/frontend test suites remain
    green.

## 12. Phase 7 — PLAN_GUID design and integration

This phase begins only after the separate `PLAN_GUID` rules are approved.

At that time:

1. update the authoritative rules documents first;
2. extend synthetic fixtures for plan/no-plan topologies;
3. extend Oracle source/destination classifier and hash state;
4. add plan-specific Preview tests;
5. add plan-safe destructive Apply tests;
6. update backend/frontend display and selection behavior as required; and
7. re-run complete Payor Configuration + PFC Copy regression coverage.

Do not backfill plan behavior into earlier phases by assumption.

## 13. Production validation phase

No production database access is required for the initial implementation.

If later work uncovers a MatrixCare fact that cannot be established from the
approved documents, schema reference capture, or synthetic tests, any production
validation must follow `PRODUCTION_DATABASE_BOUNDARY.md`:

- standalone MatrixCare-object-only harness;
- READ_ONLY or mandatory rollback-only class;
- no tool package dependency;
- no real identifiers committed;
- Preview hash before rollback-only DML;
- full restoration verification.

PFC Copy production validation scripts, if eventually needed, are validation
artifacts and not deployment code.

## 14. Implementation status checklist

| Milestone | Status |
| --- | --- |
| Product/business rules documented | COMPLETE |
| Payor Configuration/PFC Copy tool boundary documented | COMPLETE |
| Hierarchy and copy modes documented | COMPLETE |
| Copied-HER normalization documented | COMPLETE |
| `PLAN_GUID` final semantics | DEFERRED |
| Implementation plan | COMPLETE |
| Dedicated non-plan synthetic PFC Copy fixtures | NEXT |
| Read-only Oracle classifier | NOT STARTED |
| Shared-template physical replacement strategy proven | NOT STARTED |
| Oracle Preview | NOT STARTED |
| Backend Preview API | NOT STARTED |
| Frontend Preview workflow | NOT STARTED |
| Oracle Apply | NOT STARTED |
| Backend Apply API | NOT STARTED |
| End-to-end Apply UI | NOT STARTED |
| Cross-tool overwrite regression tests | NOT STARTED |
| Plan-specific integration | DEFERRED |
| Production validation, if needed | NOT REQUIRED YET |

## 15. Immediate next implementation task

The next code task is intentionally narrow:

> Add a dedicated synthetic, no-plan `837I_5010` PFC Copy fixture family and a
> read-only Oracle classifier/test that reports hierarchy level, selected copy
> scope, complete HEF membership, and copied-HER normalization without changing
> any data.

This task must not modify the working Payor Configuration resolver or Apply
logic. It establishes the foundation for PFC Copy Preview and provides the
fixture needed to prove the shared-template implementation strategy before any
PFC Copy template DML is written.
