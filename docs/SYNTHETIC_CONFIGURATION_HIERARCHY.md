# Synthetic configuration hierarchy

Payor and plan dropdowns, plan inheritance, and additive synthetic fixtures are
documented in [Payor plan configuration](PAYOR_PLAN_CONFIGURATION.md).

The default local seed is `database/05_seed_hierarchy.sql`, generated from
`database/maintenance/hierarchy_seed.json`. It contains 26 payors, 27 PFCs,
two form templates, five user templates, 17 HERs and 67 HEFs. There are no
initial payor overrides. Billing form code is `837I_5010`.

| Owner | Value Codes 39–41 | Service Facility 77 | Remarks 80 | Taxonomy 81 |
|---|---|---|---|---|
| Billing form | Off | Off | Conditional standard remarks | Off |
| Home Health form | CBSA | Inherit | Inherit | Inherit |
| Hospice form | Care-location 61/G8 | Inherit | Inherit | Inherit |
| Provider Taxonomy On user | Inherit | Inherit | Inherit | On |
| Service Facility Always On and Include Address user | Inherit | Always, address Yes | Inherit | Inherit |
| Service Facility On when not HOME No Address user | Inherit | Conditional, address No | Inherit | Inherit |
| Home Health Value Codes FIPS On user | CBSA and FIPS | Inherit | Inherit | Inherit |
| Hospice Value Codes VC 80 On user | Care-location 61/G8 and VC80/days | Inherit | Inherit | Inherit |

Inherit means no HER/HEF at that level for the record type. Off means an
explicit disabling HER. Box 77 uses three HERs (NM1, N3, N4); the others use
one each. Each HER retains its complete HEF child structure, including
unmanaged synthetic fields. User-template Value Codes replace the complete
HER configuration, not individual fields inherited from the form template.

Standard Remarks retains `G_D2300190NTE208_COUNT` and `GET_REMARKS`.
The Hospice combined recipe uses `GET_CARE_LOC_CODE` and
`GET_CARE_LOC_VAL_CODE` alongside VC80 and `GET_DISTINCT_COVERED_DAYS`.
FIPS requires CBSA. The two Value Codes user templates have a matching
form-template restriction; the other three user templates work with either
form template.

## Assignments

Names omit the common Synthetic prefix. All PFCs for a payor share its assignment.

| User profile | Home Health payors | Hospice payors |
|---|---|---|
| None | Defined LOB Payor; Hierarchy 01; PAYOR_A | Hierarchy 07; PAYOR_G; UI Demo |
| Taxonomy On | Hierarchy 02; PAYOR_B | PAYOR_H; PFC Copy Different Destination |
| Service Facility Always / address Yes | Hierarchy 03; PAYOR_C | Hierarchy 08; PFC Copy Empty Destination |
| Service Facility Conditional / address No | Hierarchy 04; PAYOR_D | Hierarchy 09; PFC Copy Empty Source |
| CBSA and FIPS | Hierarchy 05–06; PAYOR_E–F | — |
| Care-location and VC80/days | — | PFC Copy Identical Source; Identical Destination; Source; Shared Template Peer |

Each user template serves four payors; six payors use no user template.
Saved LOB matches each payor's form template: 13 Home Health and 13 Hospice.
The full GUID mapping is in `hierarchy_rebuild_preview.json`.

## Current settings and editing

Oracle current-state responses include the owner of each effective HER.
The setting panel displays Configuration level owner directly below PFC GUID
in Tier 2 Technical details. Multiple component owners are displayed separately.
Owner identifiers come from the effective HER, not the PFC's template fields.

Inherited Value Codes show their actual capabilities in Current configuration.
The proposal has an explicit Use inherited settings choice. Its read-only
checkboxes show the actual inherited capabilities, including CBSA and FIPS from
a user template or the same-payor parent of a plan. Customize starts with the
current effective capabilities. An empty custom choice requires either selecting
a capability or choosing inheritance; it must not imply an Off override.
The underlying all-false API request still means Default/inherit, not Off.
Current responses expose separate effective and inherited selections, preserving
unknown inherited capabilities as null rather than unchecked/disabled claims.
Manual settings continue through Preview/Apply and the minimal-override engine.
Template switching is not a new UI feature in this change; its future workflow
must validate template/LOB compatibility, refresh current settings and reconcile
any existing override template context before applying a switch.

## Installation and validation

Fresh-schema `database/install/install_all.sql` loads this checkpoint.
`database/tests/run_all.sql` checks the checkpoint and Value Codes recipes.
For live rollback integration checks, set `RUN_ORACLE_HIERARCHY=1` and run
`python -m pytest database/tests/test_hierarchy_checkpoint.py`.

`python database/run_poc.py reset` previews table counts; adding
`--confirm-reset` resets the local synthetic tables and loads this checkpoint.
The reset uses DELETE, and the replacement seed commits after its inserts.

Legacy adversarial fixtures remain in `02_seed_reference_data.sql` and
`03_seed_test_cases.sql`. Use `reset_legacy` and `test_legacy` only in a disposable
local test schema; they deliberately replace the approved checkpoint with the
old fixture matrix. Legacy integration tests require that fixture matrix.

The one-time rebuild used an exact before-state guard, rollback rehearsal,
complete-state comparisons and all 26 current-state checks before committing.
`hierarchy_before.json` records the synthetic recovery snapshot and
`hierarchy_rebuild_result.json` records completion. No tool-owned catalogs or
packages are intended for installation in MatrixCare production.
