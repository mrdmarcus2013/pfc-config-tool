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
on the Stage 3 checkpoint. Stage 4 remains uncommitted. The optimized package is
installed only in the local synthetic Oracle database.

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
