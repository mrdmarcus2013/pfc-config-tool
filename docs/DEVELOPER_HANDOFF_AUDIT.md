# Developer handoff audit — September 17, 2026

**Demo scope: this repository is intended for developer review as a working synthetic demonstration. The handoff priority is clear setup, behavior, and developer notes. Production readiness is not a requirement for sharing this demo.**

Start with the [demo handoff guide](DEMO_HANDOFF.md). This report preserves the September 17 technical findings and validation evidence as engineering notes. Priority labels describe the relative importance of follow-up work; they are not a requirement to turn the demo into a production release before review. The original audit used a broader release-readiness framing, which has been corrected to match the intended demo scope.

Audited repository: [mrdmarcus2013/pfc-config-tool](https://github.com/mrdmarcus2013/pfc-config-tool). GitHub `main` and the clean local checkout both pointed to `a8385cbb6ff022e1f4ebea2834f4a09a89995ec1` (Custom Provider Taxonomy, September 16). Findings refer to that commit, before this report was added.

The review covered repository inventory and history, GitHub settings accessible to the current account, setup and dependency reproducibility, API transaction handling, Oracle safety boundaries, selected engine implementation paths, frontend tests/build, and documentation. It is a risk-based engineering audit, not a claim that every execution path, historical file, or production condition has been exhaustively verified.

## Engineering follow-ups for reviewers

### H1 — High: committed frontend dependencies have known security advisories

**Evidence:** `frontend/package.json:21` pins Vite 7.1.3. `npm audit --json` reports **five high-severity affected package entries**: Vite, Rollup, PostCSS, picomatch, and nanoid. These are development/build dependencies; `npm audit --omit=dev` reports zero advisories for the production dependency set. Five is a package count, not the number of distinct vulnerabilities.

The Vite maintainer's [Windows file-deny bypass advisory](https://github.com/vitejs/vite/security/advisories/GHSA-fx2h-pf6j-xcff) includes this installed version. That advisory describes exposure when the dev server is network-accessible and the affected files are within allowed directories. The checked-in Vite configuration binds to `127.0.0.1`, reducing that exposure; this audit did not demonstrate exploitation or read secrets through the server.

**Action:** update Vite and affected transitive dependencies in the manifest and lockfile, then rerun clean installation, frontend tests/build, and the full dependency audit. At audit time npm proposed Vite 7.3.6 as a non-major fix; verify the complete resulting graph rather than treating a version change alone as closure.

**Follow-up verification:** rerun the audit after updates and document any remaining exceptions by affected path and exposure.

### H2 — High: legacy installer commands bypass the newer safety gates

**Evidence:** `database/run_poc.py:25` defines older mutation actions; `connect()` at line 140 accepts the configured Oracle host, and the dispatch loop near line 285 executes their scripts. Local-host/synthetic-data checks and explicit preview/confirmation exist for newer upgrades, but do not cover `install`, `all`, `prep3`, `install3`, `install_lob`, `install_value_codes`, or `install_remarks`.

A mocked CLI reproduction supplied `ORACLE_HOST=nonlocal.invalid`, intercepted database connections and script execution, and invoked each action without confirmation. All seven reached their configured script execution paths and returned success. No real DDL or remote connection was used for this reproduction.

**Impact:** a developer using an unintended `.env` can reach schema creation or routine replacement without the protection applied to newer commands. Oracle DDL can commit implicitly, so the runner's exception rollback is not a general undo mechanism. This conflicts with the project's preview-before-confirmation requirement for database-changing operations.

**Action:** apply one common environment/target check and preview/confirmation dispatch to every mutating command. Fresh schema installation needs its own explicit empty-schema/local-development checks; do not assume that existing fixture tables are present. Keep production validation separate from tool installation. Test that rejected targets and unconfirmed invocations cannot reach script execution.

### H3 — Medium: no automated GitHub merge validation or dependency alerts

**Evidence:** no tracked `.github` workflow files, and GitHub returned no Actions runs. The Dependabot API explicitly reported alerts disabled. The secret-scanning API reported scanning disabled. Branch-protection and ruleset APIs returned a plan restriction requiring GitHub Pro or a public repository; enforced protection could not be verified under the current private-repository plan.

**Impact:** passing local tests do not prevent future untested changes or newly vulnerable dependencies from entering `main`.

**Action:** add CI for Python tests, frontend tests/build, production-boundary checks, and dependency/secret checks. Enable supported repository security features. Require review and checks in the team's supported repository/organization setup. Keep the repository private; making it public is not a prerequisite recommended by this audit.

### H4 — Medium: the documented smoke test is not repeatable on the current demo database

**Evidence:** `RUN_ORACLE_INTEGRATION=1` with `backend/tests/test_oracle_smoke.py` produced **two failures**:

- At line 62, the test expected SYN-HIER-01 to have no form template; the current synthetic database resolved a form template.
- At line 94, the test expected the D001 example's Line of Business to be undefined; it was already Hospice.

These are fixed-fixture expectation failures. They do not establish an engine regression. Because these assertions fail early, this invocation also does not establish that the later preview assertions passed. The separate isolated Oracle tests passed.

**Action:** make the ordinary smoke check inspect valid current state without assuming editable demo settings, and keep exact seed-baseline checks in a disposable schema or isolated fixture suite. Clearly distinguish fresh-install baseline verification from repeatable application health checks. Do not reset a user's working demo just to make smoke tests pass.

### H5 — Medium: the advertised database test command does not run the full suite

**Evidence:** `database/README.md:255` describes `python database/run_poc.py test` as rerunning all installed tests. Its target, `database/tests/run_all.sql`, includes only `test_07_value_codes.sql` and `test_13_hierarchy_checkpoint.sql`. Other SQL regressions and Python Oracle suites are not included. The ordinary Python test run also skips **257 tests**, predominantly opt-in Oracle tests.

**Action:** provide an explicit test matrix and one documented developer validation entry point that reports what ran and what was skipped. Separate static/unit tests, rollback-only Oracle tests, disposable-schema mutation/DDL tests, and production harness validation. Do not simply enable every integration flag against the working demo: some legacy end-to-end tests commit cleanup, and one Copy failure test creates a trigger.

**Documentation follow-up:** identify each command's actual coverage and distinguish executed Oracle checks from skipped tests. The demo guide and database README now clarify the commands; the underlying test entry points have not changed.

### H6 — Medium: Python and Oracle installation inputs are not reproducibly pinned

**Evidence:** all six entries in `requirements.txt` are unversioned; `docker-compose.yml:4` uses Oracle `latest-lite`. The current Python environment has httpx2 2.10.0; an independent fresh install from the same requirements resolved httpx2 2.13.0. Both passed the default test suite, demonstrating that the same source already produces different dependency sets.

`pip-audit` against the original `.venv` reported three advisories on httpx2 2.10.0: PYSEC-2026-3849, PYSEC-2026-3848, and PYSEC-2026-3846. Listed fixes were 2.11.0/2.12.0. The [HTTPX2 decompression advisory](https://github.com/advisories/GHSA-8xx6-hgc6-gc2m) identifies the affected response-processing path. This audit did not establish a vulnerable application runtime path; the repository uses TestClient for tests, and the original environment was left unchanged. The fresh installation selected a version above those listed fixes.

**Action:** commit a tested Python dependency lock or constraints file including transitive versions, separate test-only dependencies where practical, and record/pin the supported Oracle image version or digest. Audit the locked set and provide a controlled update process. Refresh the older local environment after that set is approved.

### H7 — Medium: the development team does not yet have verified repository access

**Evidence:** GitHub reports a private repository. The collaborator list contains only `mrdmarcus2013` as administrator. No accepted developer-team access appeared in that response. Pending invitations were not examined.

**Action:** grant the intended team appropriate access or transfer the project through the team's approved private repository process. Validate cloning and release-asset access using a developer's account. This audit did not send invitations, change access, or publish the repository.

### H8 — Low: the handoff needs a current release/checkpoint and a consolidated limitations list

**Evidence:** GitHub has one release, `demo-video-2026-09-11`, explicitly a video prerelease targeting `ba40555`. It predates Custom Taxonomy on `main`. Repository description is empty; no license metadata, contribution guide, or ownership file was found. These are handoff/ownership decisions, not evidence of a runtime defect. A private company project does not automatically need an open-source license.

**Action:** create an agreed developer handoff checkpoint after remediation, attach the tested commit and validation results, identify maintainers, and link setup, architecture/business rules, and production limitations from a short handoff index. Confirm ownership/licensing through the team's normal process rather than inventing terms. Label the older video with its feature scope.

## Future production considerations — outside the demo scope

These are reference notes for a possible later implementation, not conditions for presenting the demo:

| Gate | Evidence and required decision |
| --- | --- |
| Authentication and authorization | `backend/app/main.py` has no authenticated host-user dependency; mutation requests accept `audit_user` from the client. The Tier 2 flag only changes presentation. Integrate trusted identity, role checks and payor/plan authorization before shared or production use. |
| Actual MatrixCare schema and ownership | The project has synthetic schema objects and tool-owned LOB/plan/template metadata. Production compatibility cannot be inferred from local Oracle success. Follow `docs/PRODUCTION_DATABASE_BOUNDARY.md`; never install tool objects merely to make a harness run. |
| Harness feature parity | The boundary document explicitly says existing harnesses need plan-aware updates. `docs/CUSTOM_TAXONOMY.md` says production harnesses have not been extended for Custom. `database/README.md` records the remaining production Service Facility rebuild-validation gap. |
| Concurrency and scale | `database/packages/pfc_copy.pkb:532` takes table-wide write-excluding locks on PFC, plan/LOB metadata, HER and HEF with NOWAIT. The generic field engine bounds hash serialization at 32,767 characters and fails on overflow. Validate real configuration sizes, lock contention, and interaction with external writers before production. |
| Deployment and operations | Current setup uses development servers and a local Oracle container. Define production serving, secrets handling, least-privilege database access, migration/recovery, logging, and operational ownership as separate team work. The Docker database port is published without a loopback-only bind; choose an explicit local-network exposure policy for developer installations. |
| Browser acceptance | Unit/render tests cover presentation and modal behavior, but browser-native end-to-end coverage is deferred in the frontend README. Obtain a current manual/browser acceptance record for the supported workflows, including Custom Taxonomy. |

## Verification performed

Environment: Windows, Python 3.13.5, Node 22.17.1. Dependency advisory results are a September 17 snapshot and may change.

| Check | Result |
| --- | --- |
| Local commit versus GitHub `main` | Exact match at `a8385cb`; worktree clean before audit |
| Default backend/database Python tests | **417 passed, 257 skipped** |
| Fresh isolated Python installation, dependency check, same default tests | **417 passed, 257 skipped**; dependency check passed; one Starlette/AnyIO deprecation warning |
| Frontend tests | **151 passed**, none skipped |
| Frontend TypeScript and production build | Passed |
| Fresh frontend copy from tracked files: `npm ci` and production build | Passed |
| Oracle configuration validation, Custom Taxonomy, plans, Value Codes controls/display, Copy source validation | **173 passed** |
| Oracle LOB resolution and Payor Copy, excluding the DDL failure-injection test | **44 passed, 1 deselected** |
| Read-only Oracle smoke suite | **2 failed**, fixture-state expectations described in H4 |
| Production boundary static checks | Passed within the default Python suite |
| Frontend dependency audit | Five high-severity affected dev/build packages; zero production-package advisories |
| Existing Python environment dependency audit | Three advisories on httpx2 2.10.0 |
| GitHub state | One remote branch (`main`); zero open PRs/issues; no Actions runs; one video prerelease |
| Local Markdown file-link check | No missing local Markdown link targets found |
| Git hygiene | `.env` ignored and untracked; no `.env`/private-key-container paths found in the checked local reachable history; `git diff --check` passed |
| Limited historical secret-pattern scan | 576 text blobs across 23 reachable commits checked for recognizable private keys, GitHub/OpenAI/AWS keys, and credential-bearing HTTP URLs; zero matches |
| Tracked synthetic snapshot inspection | Both top-level PAYORS snapshots had 26 payors, all named with the Synthetic prefix |

The secret scan is deliberately described by its coverage. It is not a comprehensive high-entropy secret/PHI detector, and zero pattern matches do not certify every historical value or release video as free of sensitive information. No secret values were printed or included in this report.

## What was not executed or changed

- No production connection, production harness execution, schema installation/reinstallation, fixture reset, or application save was performed as part of this audit.
- Oracle engine tests used their existing rollback fixtures, including restoration checks. The Copy DDL failure-injection test and legacy committing end-to-end suites were excluded.
- Fresh Python and frontend installs were verified. A completely fresh Oracle schema installation was **not** repeated; the earlier setup-document verification is historical evidence, not a new result for this audit.
- The release video's existence, metadata, size and target commit were checked; its audiovisual contents were not reviewed. Hidden/deleted GitHub objects, external forks, organization-wide controls, and pending invitations were not audited.
- During the original audit, application code, dependency manifests, `.env`, GitHub settings and access were not changed; the report was the only intended tracked-file addition. The subsequent demo-scope clarification added the demo guide and updated related documentation only. Temporary tools and clean-install copies are under ignored `.run/handoff-audit/`.

## Demo handoff priorities

1. Give reviewers the demo guide, setup instructions, feature walkthrough, and developer references.
2. Ensure the intended reviewers can access the private repository and video.
3. Explain saved demo state, current test results, known limitations, and the video's older feature scope.
4. Keep the engineering findings as a follow-up list for the team to prioritize. Treat production integration as separate future work.

The passing isolated tests provide useful evidence for the core configuration design, transaction rollback, stale-preview validation, plan scoping, and recent Taxonomy/Value Codes work. The demo is ready for discussion with these notes; the review is not a production certification.
