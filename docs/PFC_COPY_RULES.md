# PFC Copy Rules

**PFC Copy** means **Payor Format Configuration Copy**.

## 1. Scope and relationship to Payor Configuration

PFC Copy and the **Payor Configuration Tool** are separate tools that operate on
the same MatrixCare claim-configuration data.

- Payor Configuration is feature-based and applies purpose-built rules for
  supported settings.
- PFC Copy is configuration-based and replaces the approved destination
  configuration scope with configuration cloned from a selected source
  payor/PFC context.
- HER/HEF rows are not permanently owned by the tool that created them.
- A later valid operation may replace rows created by an earlier operation when
  those rows are within the later operation's scope.

Therefore:

- PFC Copy may replace Provider Taxonomy, Service Facility, Value Codes,
  Remarks, or other rows that were previously created by Payor Configuration.
- A later Payor Configuration change may delete and rebuild rows that were
  previously created by PFC Copy for that setting.
- PFC Copy must not exclude a record type merely because Payor Configuration
  currently knows how to configure it.

Provider Taxonomy, Service Facility, Value Codes, and Remarks are only the first
implemented Payor Configuration settings. The Payor Configuration catalog is
expected to expand over time, and PFC Copy must remain generic rather than
maintaining a whitelist tied to today's catalog.

## 2. Selected PFC contexts

PFC Copy operates between two explicitly selected contexts:

```text
Source:      source payor + source PFC
Destination: destination payor + destination PFC
```

The selected `PFC_GUID` identifies the exact source and destination PFC rows.
A NULL plan may be displayed as **No plan**, but final `PLAN_GUID` read/write,
precedence, and fallback behavior is intentionally deferred to a separate
approved design discussion. This document does not establish those rules.

For PFC Copy, an eligible institutional PFC must satisfy:

```sql
CPD_END_DATE > SYSDATE
AND TYPE_OF_BILL IS NULL
AND BILLING_FORM_CODE = '837I_5010'
AND DEFAULT_MEDIA_TYPE = 'E'
AND (
    USER_FORM_TEMPLATE_GUID IS NULL
    OR USER_FORM_TEMPLATE_GUID NOT IN (
        'E7BFA6270CF163DEE030007F010072AC',
        '9C3D46EEE7DB42B8AAE82B7A1038E223',
        '901B7182232A47EDAD5AB6B02F90F84C',
        'D9E9C52782F54AA29B27A058FCB6F412'
    )
)
```

`CPD_START_DATE` is not used by PFC Copy for eligibility, precedence,
tie-breaking, or automatic PFC selection.

For a selected payor:

- 0 eligible PFCs: PFC Copy is unavailable.
- 1 eligible PFC: it may be auto-selected.
- More than 1 eligible PFC: the user must explicitly select the exact PFC.

## 3. Claim-configuration hierarchy

The effective HER hierarchy is:

```text
PAYOR
  > USER TEMPLATE
  > FORM TEMPLATE
  > BILLING FORM CODE
```

Higher levels override lower levels for the same targeted configuration.

For standard claim-configuration classification:

### PAYOR level

A HER is payor-level when:

```sql
HER.PAYOR_GUID IS NOT NULL
```

This is the highest-precedence level. If a payor-level HER also has template
GUID columns populated, the populated `PAYOR_GUID` still makes it payor-level
for precedence purposes.

### USER TEMPLATE level

A non-payor HER is user-template-level when:

```sql
HER.PAYOR_GUID IS NULL
AND HER.USER_FORM_TEMPLATE_GUID IS NOT NULL
```

If both user-template and form-template GUIDs are populated, the row remains a
USER TEMPLATE-level row because user-template specificity outranks form-template
specificity.

### FORM TEMPLATE level

A non-payor HER is form-template-level when:

```sql
HER.PAYOR_GUID IS NULL
AND HER.USER_FORM_TEMPLATE_GUID IS NULL
AND HER.FORM_TEMPLATE_GUID IS NOT NULL
```

### BILLING FORM CODE level

A non-payor HER is billing-form-level when:

```sql
HER.PAYOR_GUID IS NULL
AND HER.USER_FORM_TEMPLATE_GUID IS NULL
AND HER.FORM_TEMPLATE_GUID IS NULL
```

and its `BILLING_FORM_CODE` supplies the applicable baseline.

The billing-form level is the lowest fallback level. PFC Copy does not replace
the underlying billing-form baseline as part of normal source-to-destination
copy behavior.

## 4. Generic copy behavior

PFC Copy is generic. It copies qualifying configuration regardless of whether
the record type is currently recognized by the Payor Configuration UI.

Unknown or future `RECORD_TYPE_CODE` values are data, not errors. PFC Copy must
not use Provider Taxonomy, Service Facility, Value Codes, Remarks, or future
Payor Configuration recipes to decide whether a generic record type can
participate.

The copy mode determines which hierarchy levels are replaced:

- **Copy without templates:** replace PAYOR-level configuration only.
- **Copy with templates:** replace PAYOR-level plus applicable USER TEMPLATE and
  FORM TEMPLATE configuration. The BILLING FORM CODE baseline remains in place.

## 5. HER and HEF are one configuration unit

Every copied HER is copied together with its **complete** HEF child set.

For each source HER selected for copy:

1. read the complete `HCFA_ELECTRONIC_RECORDS` row;
2. read every `HCFA_ELECTRONIC_FIELDS` row whose `ELECTRONIC_REC_GUID` belongs
   to that HER;
3. build the complete desired destination unit before DML;
4. generate a new destination `ELECTRONIC_REC_GUID`; and
5. assign that new parent GUID to every cloned destination HEF.

Do not clone only the fields currently managed by Payor Configuration. Preserve
functional HER/HEF attributes except where an approved PFC Copy normalization,
ownership, audit, or template rule explicitly changes them.

## 6. Copied HER normalization

These normalizations apply only to HER rows that have already been selected for
copy. They do not alter excluded source rows and are not source-selection rules.

### `MANDATORY_IND`

If the copied HER uses `RETURN_1`:

```text
STO_PROC_NAME = 'RETURN_1'
    -> preserve the source HER.MANDATORY_IND
```

A valid `RETURN_1` row may therefore remain either `MANDATORY_IND = 'Y'` or
`MANDATORY_IND = 'N'` according to the selected source configuration.

For every other stored-procedure value, including NULL:

```text
STO_PROC_NAME != 'RETURN_1'
    -> MANDATORY_IND = 'N'
```

### Other canonical copied-HER values

For every copied HER:

```text
CARRY_FORWARD_IND = NULL
INCLUDE_RECORD_DATA_ONCLAIM = 'Y'
```

New destination rows use new GUIDs, destination ownership metadata, insert audit
metadata for the copy operation, and cleared modification-audit fields.

## 7. Destination replacement semantics

PFC Copy is a replacement operation, not a merge operation.

For every hierarchy level included by the selected copy mode:

1. remove the destination configuration in that replacement scope;
2. build cloned source configuration for that level; and
3. apply the cloned configuration as the new destination state.

Rows that happen to be functionally identical on both sides are still part of
the replacement model; PFC Copy is not required to preserve their existing row
identities.

### Empty source is still replacement

If the source has zero qualifying HERs for a hierarchy level that is inside the
selected replacement scope, the destination configuration at that level is
cleared.

An empty source does **not** mean `NO_CHANGE`.

Example:

```text
Destination payor level before:
    C
    D
    Y

Source payor level:
    <no qualifying HERs>

Destination payor level after copy:
    <no payor-level HERs>
```

The final plan-specific definition of destination scope is deferred with the
`PLAN_GUID` design and must not be guessed.

## 8. Copy without templates

When **Copy template associations** is disabled:

1. keep the destination PFC's existing `FORM_TEMPLATE_GUID` and
   `USER_FORM_TEMPLATE_GUID` unchanged;
2. keep the destination's existing USER TEMPLATE and FORM TEMPLATE
   configuration unchanged;
3. keep the BILLING FORM CODE baseline unchanged;
4. remove destination PAYOR-level HER/HEF configuration in the approved PFC
   Copy replacement scope; and
5. clone and apply the source PAYOR-level HER/HEF configuration to the
   destination.

Source template-level HER configuration is not copied in this mode.

Conceptually:

```text
Destination templates:        KEEP
Destination template HERs:    KEEP
Destination billing baseline: KEEP
Destination payor HERs:       REPLACE with source payor HERs
```

## 9. Copy with templates

When **Copy template associations** is enabled, PFC Copy replaces both the
payor-level and template-level configuration represented by the selected source
PFC context.

The resulting destination should match the source configuration structure above
the billing-form baseline.

Example:

```text
SOURCE
Form template: A
User template: B
Payor configuration: C, D, E

DESTINATION BEFORE
Form template: A
User template: X
Payor configuration: C, D, Y

DESTINATION AFTER COPY WITH TEMPLATES
Form template: A
User template: B
Payor configuration: C, D, E
```

Operationally:

1. remove destination PAYOR-level configuration in replacement scope;
2. when the source and destination PFC template associations differ, remove the
   old destination USER TEMPLATE / FORM TEMPLATE configuration from the
   destination's effective replacement context;
3. set the destination PFC's `FORM_TEMPLATE_GUID` and
   `USER_FORM_TEMPLATE_GUID` to the source PFC's corresponding associations;
4. clone/apply the applicable source USER TEMPLATE and FORM TEMPLATE HER/HEF
   configuration for the resulting destination template context;
5. clone/apply the source PAYOR-level HER/HEF configuration; and
6. leave the BILLING FORM CODE baseline unchanged.

After a successful copy with templates, the destination must not continue to
use old destination template-level configuration that was replaced by the
source template context.

Template-level HER rows may potentially be referenced by more than one PFC. The
implementation must achieve the required effective replacement without blindly
deleting a shared template row that is still required by another PFC context.
Shared-template safety is an implementation constraint, not permission to keep
the old destination template configuration effective after the copy.

## 10. Template applicability

For identifying the template configuration associated with a selected PFC:

- **USER_TEMPLATE_VALID**: `PAYOR_GUID IS NULL`, populated
  `USER_FORM_TEMPLATE_GUID` matches the PFC user template, and the HER form
  template either matches the PFC form template or is NULL.
- **FORM_TEMPLATE_VALID**: `PAYOR_GUID IS NULL`, user template is NULL, and
  populated form template matches the PFC form template.
- **BILLING_FORM_VALID**: `PAYOR_GUID IS NULL` and both HER template GUIDs are
  NULL.
- **STALE_TEMPLATE_ASSOCIATION**: a populated template association does not
  apply to the selected PFC. It remains diagnostic and is not treated as valid.

A template-less billing-form HER remains a valid lower-level fallback against a
templated PFC, but billing-form rows are not cloned as template-level rows.

## 11. TYPE_OF_BILL

Payor HER rows with populated `TYPE_OF_BILL` remain visible in diagnostics.
Until a separate explicit rule establishes their generic copy semantics, they
are not standard PFC Copy candidates.

- Source populated `TYPE_OF_BILL`: diagnostic, not silently copied.
- Destination populated `TYPE_OF_BILL`: not silently deleted or rewritten.
- If such a row prevents the requested replacement from being proven safe, the
  operation blocks.

## 12. Preview, Apply, and atomicity

PFC Copy must support Preview before Apply.

Preview must build the complete intended destination state before mutation and
show enough diagnostics to explain copied, excluded, stale, ambiguous, and
blocked rows.

Apply must:

- re-read and revalidate the relevant source and destination state;
- reject a stale Preview/state hash before DML;
- apply the complete operation atomically;
- never leave a template-only update, partial HER copy, or incomplete HEF copy;
- verify the complete resulting state; and
- commit only after successful verification at the application transaction
  boundary.

Any ambiguity or unsafe condition blocks the entire operation rather than
producing a partial copy.

## 13. Tool interaction examples

### PFC Copy after Payor Configuration

```text
Payor Configuration creates or rebuilds settings on Payor A
        ↓
User runs PFC Copy from Payor B to Payor A
        ↓
Rows in the PFC Copy destination scope are replaced
        ↓
The cloned Payor B configuration becomes Payor A's configuration
```

### Payor Configuration after PFC Copy

```text
PFC Copy creates cloned settings on Payor A
        ↓
User changes one supported setting in Payor Configuration
        ↓
Payor Configuration performs its normal cleanup/rebuild for that setting
        ↓
The new Payor Configuration setting replaces the copied rows in its scope
```

Neither sequence is an error. The tools are independent configuration paths.

## 14. Deferred PLAN_GUID design

Final `PLAN_GUID` behavior is intentionally outside the scope of the current
documentation update. A separate approved design must establish, at minimum:

- source plan eligibility and fallback behavior;
- destination plan normalization;
- shared NULL-plan behavior;
- plan-specific replacement scope; and
- any interaction between multiple PFC rows sharing a plan.

Until those decisions are approved, do not infer new plan semantics from older
discovery scripts or from historical production patterns.

## 15. Production boundary

Standalone production validation for PFC Copy must follow
`PRODUCTION_DATABASE_BOUNDARY.md`. Production harnesses remain independent of
tool-owned packages and are validation tools, not deployment scripts.

