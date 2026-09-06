# Behavior-preserving refactor

The copy workflow and eligible destination selector were committed and pushed
to `main` as `69f3be9` before refactoring. Refactor work begins on
`refactor/stage-1-structure-tests`.

## Stage 1: structure and test isolation

Completed locally on September 6, 2026. The stage remains separate from the
pushed copy checkpoint. It was checkpointed locally as `2e6f0b2` before Stage 2.

- Extract the claim layout, field editor, Value Codes editor, and Line of
  Business control from `App.tsx` while retaining their component bodies.
- Move copy request/response models into a dedicated module and extract
  identical backend response transformations without changing transactions.
- Restore mocked frontend globals after each test.
- Give plan integration tests temporary synthetic fixtures and verify rollback
  restoration, including the plan ownership registry.
- Check that the standalone production boundary registry covers every locally
  declared tool object.
- Correct outdated documentation about PFC selection and exact plan scope.

Verification includes component-body comparison with the checkpoint, frontend
tests and build, Python unit tests, and local rollback-only plan/copy tests.
No application Oracle package or standalone production harness changes belong
in this stage.

Results: all three extracted editor bodies match the checkpoint; the OpenAPI
contract is identical; 175 Python tests passed (39 optional integration tests
skipped), 83 frontend tests passed, and the frontend build passed. Rollback
checks verified restoration of the existing synthetic configuration and plan
ownership registry. `App.tsx` decreased from 874 to 301 lines.

## Stage 2: editor and backend workflow plumbing

Completed locally on September 6, 2026, on `refactor/stage-2-workflows`, based on
the Stage 1 checkpoint. Stage 2 remains uncommitted.

Add asynchronous transition and transaction failure tests before extracting
shared lifecycle helpers. Preserve each editor's existing stale-preview policy,
API error messages, accepted input shapes, and transaction boundaries. Extract
small shared operations while keeping capability-specific validation explicit.

This stage shares the Preview request lifecycle across the standard field,
Value Codes, and Remarks editors. Apply and post-Apply verification remain in
their existing editors. Ordinary backend configuration operations share
resource management and error translation while retaining explicit commit and
rollback decisions in each operation. Health and Payor Copy retain their
distinct lifecycle policies.

Verification compares operation traces, errors, and cleanup ordering with the
Stage 1 checkpoint. It also compares the complete OpenAPI contract and read-only
responses for payor/plan contexts, both Lines of Business, configuration
overviews, copy eligibility, and copy Preview. No Oracle source changes belong
in this stage.

Results: 105 transaction characterization cases passed before and after the
backend extraction. A separate comparison matched results, SQL/binds, driver
calls, errors, and logs across 297 baseline/current scenarios. The combined
Python suite passed 280 tests (39 optional integration tests skipped), the
frontend passed 93 tests, and the frontend build passed. All ten captured
read-only API responses and the complete OpenAPI contract matched Stage 1 after
the local API restart, including the copy Preview hash.

Frontend tests exercise deferred Preview requests and cache invalidation; they
do not claim mounted-browser interaction coverage. Apply handlers, initial-load
effects, editor markup, and per-editor stale-preview behavior remain unchanged.
Backend operation bodies and signatures match the checkpoint after accounting
for resource wrappers. No new dependency or persisted configuration change was
introduced.

## Stage 3: typed Oracle internals

Introduce typed internal resolution results while retaining public cursor
interfaces. Consolidate validated Line of Business reads and clarify copy
preparation, mutation, and verification. Prove parity for hierarchy selection,
scope, HER/HEF data, errors, audit values, and deterministic hashes.

## Stage 4: measured performance work

Benchmark large synthetic copy catalogs and configuration trees. Optimize
sorting and repeated signatures only when measurements justify it. Preserve
hash ordering and keep post-mutation verification independent of pre-mutation
cached values. Measure connection overhead before considering pooling.

## Separate correctness work

The analysis identified issues whose fixes change behavior and therefore need
separate changes and regression tests:

- Null/blank direct Oracle operation modes and whitespace-only procedure names.
- Late Line of Business save callbacks after a payor switch.
- Cleanup or response validation failures after database commits.
- Invalid copy sources reported as an empty destination list and hidden copy
  error reasons.
- Consistent keyboard/focus handling across modal editors.

Production harness adaptation remains a separate effort governed by
[the production boundary](PRODUCTION_DATABASE_BOUNDARY.md); standalone scripts
must not depend on application packages.
