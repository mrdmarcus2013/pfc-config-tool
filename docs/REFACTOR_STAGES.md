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
the Stage 1 checkpoint. It was checkpointed locally as `49d1fd9` before Stage 3.

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

Completed locally on September 6, 2026, on `refactor/stage-3-oracle-internals`.
It was checkpointed locally as `72239ed` before Stage 4. The refactored packages
are installed only in the local synthetic Oracle database.

Introduce typed internal resolution results while retaining public cursor
interfaces. Consolidate validated Line of Business reads and clarify copy
preparation, mutation, and verification. Prove parity for hierarchy selection,
scope, HER/HEF data, errors, audit values, and deterministic hashes.

- Apply and Current fetch the existing 29-column public resolver output into
  one shared, column-anchored record. Public resolver SQL is unchanged.
- Remarks and Value Codes share `get_defined_lob`; both reads, normalization,
  locks, and error precedence remain unchanged. Copy retains its interleaved
  source/destination validation sequence.
- Copy has six internal phases for contexts, settings, hashes, changes,
  verification, and results. Expanding these routines reproduces the original
  statement sequence. Savepoint, locks, stale-hash check, and rollback remain
  visible in the outer operation.

Verification captured 745 read/preview cases and 35 rollback-only Apply cases
before installation. The baseline repeated successfully before the upgrade and
matched after it. Comparison includes public cursor names/types, rows, preview
hashes, complete table contents, and error identities. Only generated HER GUIDs
and fresh audit dates are normalized; insert/modification audit rules and the
operation's Oracle timestamp window are checked separately. Existing identifiers
and audit dates remain exact. Every Apply verifies restoration of all captured
configuration tables, including plan ownership.

The combined Python suite passed 303 tests (39 optional integration tests
skipped). Reference SQL recipe/hierarchy checks passed, Oracle reported no
compilation errors, and the running app's API contract and Copy Preview passed.
Existing configuration settings were preserved; no production harness changed.

For a subsequent local comparison, choose a new ignored artifact path:

```powershell
.venv/Scripts/python.exe -m database.maintenance.verify_oracle_refactor capture .run/oracle-before.json
.venv/Scripts/python.exe database/run_poc.py install_internals
.venv/Scripts/python.exe database/run_poc.py install_internals --confirm-internals
.venv/Scripts/python.exe -m database.maintenance.verify_oracle_refactor compare .run/oracle-before.json
```

The installer previews by default and replaces only application PL/SQL objects.
It does not reseed data or recreate tables. The comparison tool never commits;
it requires a local synthetic database and refuses to overwrite a baseline.

## Stage 4: measured performance work

Completed locally on September 6, 2026, on `refactor/stage-4-performance`, based
on the Stage 3 checkpoint. It was checkpointed locally as `32a025a` before the
correctness fixes. The optimized package is installed only in the local
synthetic Oracle database.

Replace the two quadratic digest-array sorts in Copy with one private stable
merge sort. Both callers construct dense arrays of non-null SHA-256 strings.
The helper uses the same PL/SQL comparison and preserves the order of ties and
duplicates. Its temporary buffer uses additional memory proportional to the
array size. JSON property sorting, SQL reads, hash inputs and versions, mutation
order, locks, audit rules, and independent post-mutation verification remain
unchanged. No signature caching, connection pooling, or new dependency is added.

Two repeatable local measurement tools support this stage:

- `database/maintenance/benchmark_copy_sort.py` extracts the actual private
  helper into anonymous PL/SQL and compares it with the original sort. Checks
  include exact ordered bytes and rolling hashes, empty/single/odd-sized arrays,
  duplicates, sorted/reverse input, and Unicode under three NLS collations.
- `database/maintenance/benchmark_payor_copy.py` creates isolated synthetic
  fixtures and measures Preview, candidate loops, and rollback-only Apply.
  Fixtures have fixed identifiers/dates; artifacts compare complete Preview
  output/hashes and normalized Apply results/table contents. Every Apply and
  scenario checks restoration, including plan ownership. Both tools preview
  without connecting by default and install no objects or persistent data.

Copy measurements use one untimed Preview warmup and three timed samples per
operation. Timings exclude fixture setup, snapshots, normalization, and rollback;
they measure direct Oracle work on one connection, not HTTP or rendered UI
latency. Candidate loops execute the full engine for each eligible synthetic
candidate. These local sequential measurements are not production capacity or
concurrency estimates.

Measured medians from the complete Copy operation:

| Synthetic source shape | Preview before / after | Apply before / after |
| --- | --- | --- |
| One record, 1,024 children | 1.570 / 1.384 s | 3.257 / 3.018 s |
| Eight records, 128 children each | 0.999 / 0.936 s | 2.793 / 2.530 s |
| One record, 4,096 children | 8.147 / 4.827 s | 17.884 / 11.251 s |

The largest workload improved by approximately 41% for Preview and 37% for
Apply. Isolated sorting of 4,096 random digests improved from approximately
801 ms to 6 ms. Small cases, context growth, and candidate growth showed mixed
timings; some post-install samples were slower. An additional old/new/new/old
package comparison with five samples per operation per block also showed mixed
small-case results, so no small-workload or dropdown speedup is claimed. The
working package was restored and configuration restoration verified afterward.

The benchmark comparisons matched full semantics across all 12 scenario runs
(three samples each), including up to eight destination contexts and 16
candidates. The 745 read/preview and 35 rollback-only Apply cases from the full
behavior verifier also matched. The five new child-multiset characterization
tests passed against the original package before the upgrade.

Final validation passed 308 Python tests (39 optional integration tests skipped).
The full behavior comparison passed again after the alternating package checks
and regression suite. Oracle reported no compilation errors; the installed Copy
body matches the working file. The running Vite/API health, Copy Preview hash,
three destination contexts, and nine eligible destinations matched the baseline.
All persisted configuration remained unchanged. Frontend/backend application
code and production harnesses were not modified in this stage.

Connection measurements used the existing catalog and real Python service
methods, with a fresh Thin connection per request. Median connection time was
18.27 ms (14.76-38.92 ms across nine samples); full Preview was 96.03 ms and
eligibility was 446.87 ms for 29 candidates, nine eligible. Paired connection
time represented 27.84% of Preview and 6.04% of eligibility. No pool was tested;
potential savings are only an upper bound. Pooling is deferred. Signature
caching is also deferred because direct Oracle Preview callers can have
different read semantics, and Apply must independently re-read mutated state.

Example commands (choose unused artifact paths):

```powershell
.venv/Scripts/python.exe -m database.maintenance.benchmark_copy_sort
.venv/Scripts/python.exe -m database.maintenance.benchmark_copy_sort --run
.venv/Scripts/python.exe -m database.maintenance.benchmark_payor_copy
.venv/Scripts/python.exe -m database.maintenance.benchmark_payor_copy --run --output .run/copy-before.json
.venv/Scripts/python.exe database/run_poc.py install_copy
.venv/Scripts/python.exe database/run_poc.py install_copy --confirm-copy
.venv/Scripts/python.exe -m database.maintenance.benchmark_payor_copy --run --baseline .run/copy-before.json --output .run/copy-after.json
```

For the extended workloads, add identical arguments to both benchmark runs:
`--records 8 --children 128 --contexts 1 --candidates 1`, or
`--children 4096 --contexts 1 --candidates 1`. Use separate artifact paths for
each workload.

The full behavior verifier from Stage 3 is also run before and after installation.
Copy regression tests additionally cover zero/single/duplicate child rows,
insertion-order independence, removing one duplicate, stale-hash rejection, and
rebuilding the exact child multiset.

## Correctness pass: Oracle validation and save results

Completed locally on September 6, 2026, on `fix/config-validation-save-results`,
after the Stage 4 checkpoint. It was checkpointed locally as `b1304ed` before
the context-switch and Copy feedback pass. These intentional
corrections remain separate from the behavior-preserving refactor commits.

- Reject null, blank, unknown, and overlong invalid Oracle operation modes with
  the existing invalid-mode error before resolution or mutation. Valid modes
  retain case/space normalization and existing expected-hash checks.
- Treat a space-only procedure name like NULL when enforcing HER mandatory
  safety. Preserve RETURN_1, complete source/unmanaged HEF content, and Default's
  refusal to inherit unsafe records.
- Validate ordinary save responses with their existing public models and JSON
  serialization before commit. This covers generic options, Value Codes,
  Remarks, initial Line of Business saves, and Line of Business changes.
- Preserve Copy's successful response after a confirmed commit if connection
  cleanup fails. Cleanup also preserves the original operation error on failure.
  A Copy cursor-close failure before commit still prevents saving. Read-only
  Copy results survive cleanup errors without changing eligibility rules.

The old implementation reproduced 18 failures among 37 new rollback-only Oracle
tests, nine ordinary-response failures, and Copy cleanup/serialization failures.
All 37 Oracle regressions pass with the local upgrade; the normal 745 read/preview
and 35 Apply behavior comparisons still match, including complete stored rows,
hashes, and audit rules. Synthetic test changes and plan ownership are restored.

Final verification passed 377 Python tests (39 optional integration tests
skipped), including 20 ordinary-response and 12 Copy failure-injection cases.
Those cases include actual API responses for rejected malformed saves and
successful saves with cleanup errors. After restarting the local backend, all
14 captured API/schema responses matched, including Preview hashes and Copy
eligibility. Oracle reported no compilation errors and installed sources match
the installer output. Persisted configuration remains unchanged. Independent
review confirmed the preflight serialization matches the installed API stack.

The targeted local installer previews by default and replaces only two existing
PL/SQL objects, without changing schema tables or stored configuration:

```powershell
.venv/Scripts/python.exe database/run_poc.py install_validation
.venv/Scripts/python.exe database/run_poc.py install_validation --confirm-validation
$env:RUN_ORACLE_VALIDATION='1'
.venv/Scripts/python.exe -m pytest database/tests/test_configuration_validation.py -q
```

This pass addresses failures after a confirmed commit and validation that can
run before commit. A lost commit acknowledgement or lost HTTP response can still
leave the save outcome uncertain; this pass does not add reconciliation or
automatic retries.

## Correctness pass: context switching and Copy feedback

Implemented locally on `fix/context-switch-copy-feedback`, after `b1304ed`.
It was checkpointed locally as `31a611c` before the keyboard/focus pass.
These changes have not been pushed.

- Give each mounted Line of Business control its own request lifetime. Late
  Save, Preview, and Apply responses cannot update a removed control or release
  a newer request, including when switching from A to B and back to A.
- Invalidate configuration caches after a successful original-payor save and
  refresh the currently displayed payor. Do not assign the old save response to
  the new payor. Current reads discard stale success, error, and loading updates;
  a failed context switch also refreshes the original payor.
- Validate Copy's source once before examining destinations, in the same
  read-only transaction. Invalid sources return an actionable error even when
  the catalog has no candidates. A valid source with no eligible destinations
  retains the existing empty-list response.
- Show approved, specific Copy error reasons through an exact-message allowlist.
  Unrecognized messages still receive safe fallback wording. Full destination
  Preview and Apply checks, hashes, locking, and replacement behavior remain
  unchanged.

Frontend verification passed 105 tests and the production build/typecheck.
Eight new deferred Line of Business tests exercise the actual request/current-read
helpers, cache invalidation, A-to-B-to-A switching, and failed-switch refresh.
Four Copy feedback tests cover specific blockers, API error propagation, safe
fallbacks, and the existing stale-preview message. No browser was available;
these checks do not claim mounted-browser interaction coverage.

Final verification passed 429 Python tests (39 optional integration tests
skipped), including 34 new rollback-only source-validation cases and 18 backend
eligibility cases. The null-entry-date fixture was removed because the local
schema's NOT NULL constraint prevents constructing that state; the shared
missing-date guard remains unchanged. No schema constraint was relaxed.

All 745 read/preview and 35 rollback-only Apply cases match the pre-change
baseline, including full rows, hashes, and audit rules. After restarting the
local backend, all 14 captured API/schema responses also match. An invalid-source
request through Vite and the running API now returns a specific safe error;
all 16 approved backend Copy messages preserve their exact frontend feedback.
Oracle reports no compilation errors, installed Copy sources match the working
files, and persisted configuration and plan ownership remain unchanged.
Independent backend, Oracle, and frontend reviews found no material issues.

## Correctness pass: modal keyboard and focus handling

Implemented locally on `fix/modal-keyboard-focus`, after `31a611c`. This pass
remains uncommitted and has not been pushed.

- Share focus management across ordinary field editors, Value Codes, Remarks,
  Copy, nested Apply confirmations, and the Line of Business reset dialog.
  Preserve each surface's existing Close, Cancel, Go Back and busy-state policy.
- Move focus into a newly opened dialog, keep Tab and Shift+Tab within the
  topmost dialog, and let Escape perform that dialog's existing dismissal action.
  Nested confirmation Escape leaves its parent editor open. Confirmation focus
  starts on Cancel or Go Back, including when technical details precede it.
- Return focus to the opener when it remains usable. An unavailable nested
  opener falls back to its parent dialog; an unavailable final opener falls
  back to the existing page heading. Recover focus when an asynchronous result
  removes or disables the focused control.
- Capture Copy's launcher explicitly before opening can disable it. Recheck an
  unavailable final opener after React finishes the closing commit, without
  stealing focus from a newer modal or another deliberate focus change.
- Keep one Line of Business modal across warning/confirmation transitions to
  retain its original opener. Refocus the safe action when the stage changes.
- Coordinate body scroll locking and event cleanup across nested dialogs,
  Strict Mode effect replay, and parent-before-child teardown.

The shared implementation adds no dependencies and does not change API requests,
Preview/Apply guards, configuration values, or database code. Its keyboard and
focus behavior follows the [WAI-ARIA modal dialog pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/).

Verification passed all 127 frontend tests and the production build/typecheck.
The 22 new focus tests exercise the actual controller against a simulated DOM,
plus server-rendered surface attributes. Coverage includes nested Tab/Escape,
hidden and disabled controls, radio groups, collapsed details, stage changes,
removed controls, explicit Copy opener capture, deferred restoration, and
Strict Mode cleanup. Existing editor rendering checks now also include Remarks;
its relative imports use the explicit extensions required by the Node test
runner. A comparison confirmed all 20 named editor handlers/request callbacks
match `31a611c`. Independent review found and verified fixes for Copy's opener
timing, with no remaining material findings. Backend and Oracle files are unchanged.

Live browser verification remains pending. The dedicated browser connection
reported no surfaces. Computer Use later found the running PFC Chrome window but
stopped because it could not determine the current URL sufficiently to enforce
its browser policy. No alternate browser-control route was used after that stop.

## Remaining verification

- Check keyboard and screen-reader behavior in a connected browser: all editor
  launchers; nested confirmation Cancel/Apply; Tab through radios, textarea,
  disabled fieldsets and collapsed details; Copy during/after save; Line of
  Business warning/confirmation/back; return after payor switching.

Production harness adaptation remains a separate effort governed by
[the production boundary](PRODUCTION_DATABASE_BOUNDARY.md); standalone scripts
must not depend on application packages.
