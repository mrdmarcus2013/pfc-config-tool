# Payor Copy rules

Approved September 6, 2026. This contract supersedes earlier copy modes and
explicit-PFC-selection proposals. Copy is a separate configuration operation;
ordinary field editing must never select another payor as its source.

## User workflow

The destination dropdown includes only synthetic catalog payors that pass the
Oracle copy Preview for the selected source payor and plan. Eligibility runs in
one read-only transaction and includes every current destination context. The
panel reloads eligibility when its source changes and provides loading, retry,
and empty-list feedback. Preview and Apply still revalidate; appearing in the
dropdown does not reserve or authorize a database change.

COPY PAYOR SETTINGS opens a side panel from the configuration header. The loaded
payor and optional plan are the fixed source. The destination is a different,
existing payor with a current no-plan configuration. No destination plan can be
selected. New payor, plan and PFC creation are outside this operation.

Preview is read-only. The panel lists destination contexts, template changes,
settings to copy/keep/remove and plan overrides included in removal. Acceptance
explicitly confirms the replacement and plan cleanup. Apply is one transaction.
Changing destination invalidates preview and acceptance. Success refreshes the
destination payor-level context in the main tool.

## Preconditions and context selection

- Source and destination payors must differ.
- Both must have defined, identical Line of Business; Copy never changes LOB.
- Billing forms must match. The supported form is 837I_5010.
- For the source payor/plan and every destination context, select the newest
  REC_ENT_DATE among current electronic, null-TYPE_OF_BILL PFCs. Ties and missing
  dates block; CPD_START_DATE never breaks a tie.
- Validate plan ownership in Oracle, independently of the UI.
- Require the destination no-plan PFC and a current PFC for every destination
  plan with current configuration or an override scheduled for removal.
- Historical/non-winning PFC rows are not updated.
- Unsupported bill-type records and destination records for other billing forms
  block rather than being silently discarded.

## Template associations

Set FORM_TEMPLATE_GUID and USER_FORM_TEMPLATE_GUID on every current authoritative
destination PFC to the selected source PFC's respective values. Source NULL clears
that association. Leave already matching associations unchanged. Never update
REC_ENT_DATE during copy; use modification audit fields for PFC changes.

Shared user/form-template HER and HEF records and billing-form baseline records
are never copied, deleted or modified. Updating the associations causes each
destination context to use the source's template hierarchy. Payor-type-specific
applicability is still evaluated separately at the destination.

## Combined source override set

Read applicable source payor-defined HERs (null plan) and selected-plan HERs.
For each applicable logical record, the exact selected plan wins over the payor
record as a complete HER/HEF unit. Do not merge individual HEFs across levels.
A no-plan source contributes only payor-defined records. Other source plans
are excluded. Inapplicable template associations are not source candidates.
Unknown/future record types participate without a supported-field whitelist.
Ambiguous winners block instead of deduplicating by child content.

The selected configuration context, billing form, record type and applicable
hierarchy determine identity. Multiple applicable records at the same winning
level are conservatively blocked. Complete source effective state is also read
through the generic template/billing hierarchy for final-equivalence validation.

## Destination replacement

- Replace destination payor-defined settings with the combined source override
  set; remove destination-only payor records in the supported scope.
- Clear ALL destination plan-defined overrides in that scope, including types
  the current field-editing UI does not recognize.
- An empty source override set clears the destination override set.
- Preserve exactly one canonical matching destination payor record and its HEFs.
  Remove duplicated, stale, differing or extra destination records.
- Each new HER receives its own ELECTRONIC_REC_GUID, the destination PAYOR_GUID,
  PLAN_GUID=NULL, and the destination's authoritative PAYOR_TYPE_GUID.
- Clone every HEF, relinking it to the new parent. Preserve all unmanaged fields.
- Source HER/HEF and PFC records remain unchanged.

Copied HERs retain functional source values except these approved adjustments:
non-RETURN_1 procedures (including NULL) require MANDATORY_IND=N; RETURN_1 preserves
the source mandatory value; CARRY_FORWARD_IND=NULL; INCLUDE_RECORD_DATA_ONCLAIM=Y.
New HER/HEF rows receive new insert audit metadata and cleared modification audit
fields. Preview reports settings needing standard safety adjustments.

## Equivalence, hashing and atomicity

Build and compare the prospective complete effective state for every destination
context before DML. Compare complete HER and HEF content, ignoring only ownership,
applicable template identity and audit fields when testing effective equivalence.
Allow the documented copied-HER normalizations. Inherited unsafe sources block.
Unexplained differences, including payor-type-dependent inherited records, block.

Canonical retained-record comparison includes destination ownership/template
metadata. JSON comparisons are independent of property order. Child records are
compared as complete multisets, preserving duplicates and unmanaged attributes.

The preview hash covers source/destination payors, all their PFC and ownership
rows, LOB metadata, relevant HER/HEF state, generic sources and selected winners.
It uses an ordered stream of SHA-256 row digests rather than one bounded state
string. Large complete configurations do not share the field engine's aggregate
32,767-character limit.

Apply locks, re-reads, rebuilds and rejects a stale hash before DML. It deletes
child rows before parents, updates template associations, inserts complete cloned
units, and verifies canonical destination rows and actual current PFC associations
plus complete effective equivalence. Failures roll back every change. Only the
backend commits after Oracle success and response validation.

The initial local implementation uses brief table-level write-excluding locks
for PFC, ownership, LOB, HER and HEF tables, plus ordered source/destination payor
locks. NOWAIT reports a busy operation safely. This deliberately serializes
configuration writes during whole-payor Apply; narrower locking is future work
if measured usage requires it.

## Local deployment and tests

From the repository root:

```powershell
.venv/Scripts/python.exe database/run_poc.py install_copy
.venv/Scripts/python.exe database/run_poc.py install_copy --confirm-copy
.venv/Scripts/python.exe -m database.maintenance.seed_payor_copy
.venv/Scripts/python.exe -m database.maintenance.seed_payor_copy --apply
$env:RUN_ORACLE_COPY='1'
.venv/Scripts/python.exe -m pytest database/tests/test_payor_copy.py -q
```

The first command in each pair previews. Package installation is DDL but does not
change configuration data. Demo seeding adds isolated synthetic records, rehearses
with rollback, and never overwrites existing fixture IDs.

Use Synthetic Copy Demo Source / Working Source Plan and Synthetic Copy Demo
Destination. The source combines parent Remarks and plan-specific Taxonomy,
Service Facility, Value Codes and an additional unknown setting. The destination
has different template associations, plan overrides, an extra setting, and an
older PFC that must remain untouched. Tests restore configuration after each copy.
Actual UI acceptance intentionally persists changes to the selected demo payor.

The local implementation uses tool-owned ownership/LOB metadata. Existing
production harnesses are not copy deployment scripts and must not be used to
validate this operation. Production integration requires separately validated
MatrixCare objects and the standalone production boundary.
