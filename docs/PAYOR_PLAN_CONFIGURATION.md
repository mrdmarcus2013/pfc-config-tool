# Payor plan configuration

Approved September 6, 2026. This specification supersedes older PFC-selection
and legacy-null-plan customization statements in the canonical rules.

## Ownership, selection and inheritance

Each plan has exactly one owner payor. The local synthetic model records that
relationship in `PFC_CONFIG_PLANS`, with an immutable ownership trigger and
composite foreign keys from PFC and HER. The PFC insert trigger registers new
synthetic plans and rejects ownership conflicts. This table and these triggers
are tool-owned local objects, not validated MatrixCare production objects.

The selected payor and plan determine the editing scope. Null plan means
**Payor-level settings**. A populated plan means **Plan settings**. Oracle checks
ownership independently of the UI. It selects eligible exact payor/plan PFCs,
using greatest `REC_ENT_DATE`; a tied greatest date or a missing eligible entry
date blocks. There is no fallback from a plan PFC to a null-plan PFC.
`CPD_START_DATE` is not a selection authority. `PAYOR_TYPE_GUID` comes from PAYORS.

Effective HER precedence, subject to template applicability, is:

1. Exact payor plan.
2. Same payor, null plan (Payor Defined).
3. Applicable user template.
4. Applicable form template.
5. Billing-form source.

For plan editing, the source is the effective configuration below the plan,
including its own payor's null-plan HER. For payor editing, the source remains
the non-payor template hierarchy. Another payor is never a source. Null-plan
payor records are an intentional parent level, not obsolete data to clean up.

Default removes only overrides at the selected editing level and inherits the
complete safe parent configuration. Explicit settings clone the full source
HER/HEF and apply managed overlays and safety invariants. If the desired state
equals the parent, the override is removed. Parent, sibling and other-payor
records are excluded from plan cleanup. Multi-HER changes remain atomic.

Preview hashes include the selected plan, PFC and entry date, complete inherited
and desired configuration, exact-plan cleanup state and action. Apply locks and
re-resolves before comparing the hash. Parent changes or a different winning PFC
invalidate affected previews. PFC changes acquire the same payor lock as Apply,
preventing a concurrent new PFC winner during mutation. Line of Business remains payor-wide; its existing
confirmed change workflow resets managed overrides across all plans.

## UI

The header order is **Payor dropdown, Plan dropdown, Billing Form display**.
Only owned plans appear. Payor selection resets to Payor-level settings.
Changing context resolves Oracle context, discards confirmed open-editor work,
clears previews/caches and reloads current settings. Failed resolution keeps the
previous context and displays an error. Technical identifiers remain in Tier 2
details. The local selector still exposes only synthetic payors; production
authorization and discovery are outside this local implementation.

## Local installation and fixtures

The development schema needs CREATE TABLE, CREATE PROCEDURE and CREATE TRIGGER.
From the repository root:

```powershell
.venv/Scripts/python.exe database/run_poc.py install_plans
.venv/Scripts/python.exe database/run_poc.py install_plans --confirm-plans
.venv/Scripts/python.exe -m database.maintenance.seed_payor_plans
.venv/Scripts/python.exe -m database.maintenance.seed_payor_plans --apply
```

The first command in each pair previews. The upgrade performs Oracle DDL and
therefore is not transactionally reversible; it preserves existing configuration
rows. Fixture application rehearses with rollback before committing. It adds two
payors, six named plans and ten PFCs without replacing existing data. Existing
fixture IDs block reseeding to protect subsequent user edits.

Choose **Synthetic Plan Demo Home Health** or **Synthetic Plan Demo Hospice**:

| Selection | Initial configuration |
|---|---|
| Payor-level settings | Taxonomy On |
| Inherited Plan | Inherits the payor and template settings |
| Custom Plan | Taxonomy Off, Service Facility always with address, custom Remarks, LOB-specific Value Codes |
| Alternate Plan | Service Facility conditional without address; inherits Taxonomy |

Custom Plan has a second, older-entry PFC with a later CPD start date to prove
that entry date, not CPD start date, controls selection. Negative cases run only
inside rollback tests and do not leave broken dropdown options.

```powershell
$env:RUN_ORACLE_PLANS='1'
.venv/Scripts/python.exe -m pytest database/tests/test_payor_plans.py -q
```

The reference hierarchy SQL checks template-source integrity and permits
interactive payor/plan overrides. The optional original fingerprint test still
requires the pristine baseline snapshot and is not an interactive health check.
Standalone production harnesses have not been upgraded for this hierarchy and
must not be used to validate plan changes or cleanup affecting plan-owned rows.
Production adaptation must use validated MatrixCare ownership objects and remain
standalone under the production boundary.
