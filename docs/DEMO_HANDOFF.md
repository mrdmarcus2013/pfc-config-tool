# Demo handoff and developer notes

This project is a working demonstration for developer and stakeholder review.
It uses synthetic data in local Oracle to show how selected claim settings can
be edited with plain-language controls, reviewed in Preview, and saved together.
The purpose of this handoff is to explain the implemented behavior, make the
demo repeatable, and support discussion of the design. Production deployment
and host integration are future work, not acceptance criteria for this demo.

These notes describe the feature set through `a8385cb` (September 16, 2026).

## Where to start

| Need | Reference |
| --- | --- |
| Install on a new Windows computer | [Complete setup walkthrough](FRESH_COMPUTER_SETUP.md) |
| Restart an existing installation | [Stop and restart](FRESH_COMPUTER_SETUP.md#12-stop-and-restart-without-reinstalling) |
| Watch without installing | [September 11 demo video](https://github.com/mrdmarcus2013/pfc-config-tool/releases/tag/demo-video-2026-09-11) |
| Discuss behavior with developers, managers, or users | [Demonstration Q&A](VIABILITY_DEMO_QA.md) |
| Understand test results and engineering follow-ups | [September 17 review notes](DEVELOPER_HANDOFF_AUDIT.md) |

The repository and video are private; reviewers need repository access.
The video predates Custom Taxonomy. The written feature descriptions below
include that addition.

## What is implemented

| Area | Demonstrated behavior |
| --- | --- |
| Payor and plan selection | Linked synthetic payor/plan dropdowns. All Plans edits shared payor settings; a named plan edits that plan's settings. |
| Line of Business | One Home Health or Hospice value per payor. Changing an existing value requires review and clears the managed overrides across that payor's plans. Initial assignment preserves existing settings. |
| Provider Taxonomy, box 81cc | None, Standard provider lookup, or a fixed Custom code of exactly 10 ASCII letters/digits. Custom codes are normalized to uppercase. |
| Service Facility, box 77 | Always, conditional on care location not being HOME, or never; address included or omitted where applicable. |
| Value Codes, boxes 39-41 | Home Health CBSA/FIPS controls; Hospice care-location, patient-entered, and covered-days choices with the documented dependencies. |
| Remarks, box 80 | Standard remarks or saved custom text; blank custom text is rejected. |
| Copy Payor Settings | Review copying from a selected payor/plan to another eligible payor, including destination plan cleanup, then confirm. |
| Tier 2 details | The same ordinary workflow with collapsed Technical Details for investigating configuration context. |

The remaining claim boxes provide layout/context and are not configurable yet.
The demo does not create payors or plans through the UI, generate claims, submit
claims, or verify reimbursement outcomes.

## Suggested walkthrough

After the setup guide's optional plan and copy examples have been installed:

1. Open the normal view at `http://127.0.0.1:5174/` or Tier 2 at
   `http://127.0.0.1:5173/`. Confirm that the payor catalog and current settings
   load. Tier 2 is enabled at frontend startup, as shown in the setup guide.
2. Select **Synthetic Plan Demo Home Health** and **All Plans**. Explain that
   the screen shows effective settings, including settings supplied by the
   existing configuration hierarchy. Select a named plan to show the scope.
3. Open Value Codes, change CBSA/FIPS, and select **Preview**. Show the dependency
   between FIPS and CBSA. Cancel to leave the saved setup unchanged.
4. Open Provider Taxonomy, choose Custom, and enter `SYN000000A`. Explain that
   this is a synthetic format example, not a verified taxonomy code. Preview
   the change. If demonstrating persistence, confirm Apply, close, and reopen
   the field to show the saved value. Record the previous setting first.
5. Show the Service Facility and Remarks choices. A synthetic remark such as
   `Synthetic demo remark` is sufficient; no patient or claim data is needed.
6. Select **Synthetic Copy Demo Source** and **Working Source Plan**. Choose
   **COPY PAYOR SETTINGS**, then **Synthetic Copy Demo Destination**. Preview
   the changes and destination plan cleanup. Cancel unless you intend to save
   the replacement. Copy leaves the source unchanged.
7. In Tier 2, expand Technical Details to discuss ownership and inheritance.
   Keep the ordinary workflow focused on settings and consequences.

Preview does not save changes. Apply and Accept and Copy save real changes to
the local synthetic database. There is no historical Undo. Saved settings
survive restarts, so an already-used demo need not match fresh-seed screenshots
or fixed fixture expectations. Do not reinstall or reset simply to restart it.

## Developer code map

| Layer | Responsibility | Starting files |
| --- | --- | --- |
| React/TypeScript | Context selection, effective settings, proposal editors, preview and confirmation | [App](../frontend/src/App.tsx), [workflow helpers](../frontend/src/app/workflow.ts), [API client](../frontend/src/api/client.ts) |
| FastAPI | Request validation, Oracle calls, safe responses, and commit/rollback | [Routes](../backend/app/main.py), [models](../backend/app/models.py), [configuration service](../backend/app/services/configuration.py), [Copy service](../backend/app/services/payor_copy.py) |
| Oracle | Authoritative source resolution, desired-state comparison, preview hashes, atomic changes | [Resolver](../database/packages/pfc_config_internal.pkb), [Apply engine](../database/procedures/03_pfc_apply_option.sql), [Copy engine](../database/packages/pfc_copy.pkb) |
| Local examples | Synthetic schema, initial hierarchy, optional plan/Copy fixtures | [Database notes](../database/README.md), [hierarchy](SYNTHETIC_CONFIGURATION_HIERARCHY.md), [plan examples](PAYOR_PLAN_CONFIGURATION.md) |

The normal flow is current settings -> proposal -> Preview -> confirmation ->
Apply -> refreshed current settings. Oracle checks that the reviewed state
still matches before saving. HER records and their HEF fields change together.
The API validates the public response before committing. React does not
implement its own version of the Oracle resolution engine.

Read the [engine rules](CLAIM_CONFIGURATION_ENGINE_RULES.md) before changing
generic behavior. [Payor Copy rules](PFC_COPY_RULES.md) define the explicit
exception allowing one payor to supply another payor's settings.
[Custom Taxonomy notes](CUSTOM_TAXONOMY.md) include the upgrade for existing
installations; pulling frontend/backend code alone does not update Oracle.

## Validation notes

The September 17 review of `a8385cb` recorded:

- 417 default Python tests passed; 257 opt-in tests were skipped.
- 151 frontend tests passed; TypeScript checking and production build passed.
- 217 selected live Oracle checks passed using rollback fixtures.
- Clean Python and frontend installations passed their applicable checks.
- Two read-only Oracle smoke tests failed because they expected fixed demo
  settings that differed from the current database. The detailed evidence is
  in the [review notes](DEVELOPER_HANDOFF_AUDIT.md).

For routine checks that do not require Oracle, run from the repository root:

```powershell
.\.venv\Scripts\python.exe -m pytest backend/tests database/tests -q
Set-Location frontend
npm.cmd test
npm.cmd run build
Set-Location ..
```

Leave `RUN_ORACLE_*` opt-in flags unset for that routine check. Skips are
expected; they do not represent executed database tests. Oracle suites have
different requirements: some roll back, some commit fixture cleanup, and one
Copy failure-injection test creates a trigger. Review the specific suite before
enabling it. `database/run_poc.py test` runs two selected SQL scripts, not the
complete Python/Oracle regression suite.

## Known limitations and useful review questions

- The database is a synthetic model of the known MatrixCare configuration
  relationships. LOB storage, plan ownership, and template-name catalogs include
  tool-owned additions. Discuss how those responsibilities would fit the host.
- Tier 2 is a local display setting, not authentication. The demo supplies its
  audit identity through the development launch context.
- One LOB applies to a payor and all its plans. Copy clears destination plan
  overrides in scope. Confirm these business choices with the reviewers.
- The Remarks limit is provisionally 100 characters. Custom Taxonomy validates
  format, not membership in the NUCC code set.
- Browser-native automated coverage is deferred; the recorded test results do
  not substitute for checking the current walkthrough in a browser.
- Dependency updates, more repeatable test fixtures, common installer safeguards,
  CI, and version pinning are engineering follow-ups in the review notes. They
  are not additional features promised for this demonstration.

The standalone files under `database/production_tests/` are separate validation
references, not demo setup steps. Their use is governed by the
[production database boundary](PRODUCTION_DATABASE_BOUNDARY.md). Production
hosting, authorization, schema approval, and operating procedures belong to a
future implementation discussion.
