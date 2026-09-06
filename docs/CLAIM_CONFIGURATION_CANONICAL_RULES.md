# PFC Configuration Tool — Canonical Claim Configuration Rules

The current [Payor Copy rules](PFC_COPY_RULES.md) supersede older copy-specific
sections below, including copy modes, PFC selection and plan replacement scope.

**Status:** Canonical architecture and business-rule reference  
**Scope:** Institutional `837I_5010` claim configuration, PFC customization, and Payor Copy  
**Audience:** Application developers, database developers, test authors, and production-validation authors

This document records the intended behavior of the PFC Configuration Tool. It consolidates the current generic configuration rules with the plan-context and Payor Copy decisions established from production observations.

When this document conflicts with older discovery scripts, preview/apply harnesses, exploratory notes, or historical MatrixCare data patterns, this document governs the **intended application behavior**. Existing scripts may need to be updated to conform.

Production observations explain why some read rules are intentionally tolerant. They do not redefine the canonical write model.

---

## September 6, 2026 customization amendment

[Payor plan configuration](PAYOR_PLAN_CONFIGURATION.md) supersedes this document's
older explicit-PFC selection and legacy-null fallback customization rules:
select the newest REC_ENT_DATE among eligible exact payor/plan PFCs; block ties
or missing entry dates. Null-plan payor HERs are the maintained Payor Defined
parent level. Plan Default removes only exact-plan overrides and inherits that
parent. Plan ownership is unique to one payor. The older Payor Copy discussion
below is not authorization to change or implement copy persistence.

## 1. Core principles

1. **The selected PFC is the configuration context.** A payor or plan label alone is not sufficient when multiple eligible PFC rows exist.
2. **Never guess between PFC contexts.** Ambiguous resolution blocks the operation.
3. **Historical plan-null HER rows are valid fallback input.** They are not evidence that plan-specific configuration should remain plan-null going forward.
4. **New and rebuilt payor-specific HER rows are canonicalized to the selected PFC plan.**
5. **Another populated plan is out of scope.** A configuration operation for Plan A must not consume or mutate a HER explicitly assigned to Plan B.
6. **Exact plan wins over legacy NULL fallback** for the same applicable logical HER identity.
7. **Template applicability and plan applicability are separate dimensions.** A HER must satisfy both before it can participate in a selected PFC context.
8. **Unknown record types are data, not errors.** Payor Copy is generic and is not limited to record types currently recognized by the customization UI.
9. **HER and HEF rows are a unit.** When a HER is cloned, its complete HEF child set is cloned before managed overlays are applied.
10. **Preview/apply must fail safely.** Missing, ambiguous, stale, or unsupported states are surfaced rather than guessed.

---

## 2. MatrixCare objects and authoritative fields

The tool's relevant MatrixCare objects are:

- `PAYORS`
- `PFC`
- `HCFA_ELECTRONIC_RECORDS` (`HER`)
- `HCFA_ELECTRONIC_FIELDS` (`HEF`)
- `LINKING_FORM_LU` only where needed for diagnostic/field discovery

### 2.1 Authoritative relationships

- `PAYORS.PAYOR_TYPE_GUID` is authoritative for the selected payor.
- `PFC.PAYOR_GUID` identifies the payor owning a PFC.
- `PFC.PLAN_GUID` defines the selected PFC's plan context; NULL means **No plan**.
- `HER.PAYOR_GUID` identifies a payor-specific HER override when populated.
- `HER.PLAN_GUID` identifies the plan assignment of a payor-specific HER when populated.
- `HEF.ELECTRONIC_REC_GUID` belongs to its parent `HER.ELECTRONIC_REC_GUID`.

The database may not declare every logical relationship as a foreign key. Application logic must not infer that a missing database constraint means the relationship is unimportant.

### 2.2 Line of business

`HOME_HEALTH` / `HOSPICE` is tool metadata where MatrixCare does not provide an authoritative production field for the required distinction. Production harnesses may therefore require line of business as a manual input. Tool-owned LOB metadata must not be assumed to exist in standalone MatrixCare production scripts.

---

## 3. Eligible PFCs

For this tool, an eligible institutional PFC satisfies exactly:

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

### 3.1 `CPD_START_DATE`

`CPD_START_DATE` is **not** an eligibility criterion and must not be used to infer the intended PFC. In observed PFC creation behavior it is not a reliable business-selection signal.

Do not add:

```sql
CPD_START_DATE <= SYSDATE
```

Do not resolve ambiguity by selecting the newest `CPD_START_DATE`.

### 3.2 PFC selection

For a selected payor:

- **0 eligible PFCs:** configuration is unavailable.
- **1 eligible PFC:** it may be auto-selected.
- **More than 1 eligible PFC:** the user must explicitly select a PFC context.

The selected `PFC_GUID` is authoritative. `PLAN_GUID` is part of the context and UI label, but it must not be assumed to uniquely identify a PFC row. Multiple eligible PFCs may share the same populated `PLAN_GUID`.

A NULL `PFC.PLAN_GUID` is displayed as **No plan**.

There is no implicit fallback from a selected plan PFC to a no-plan PFC, or vice versa. The operation acts on the explicitly selected eligible PFC.

---

## 4. Template applicability

Template applicability is evaluated against the selected PFC before a HER can participate in customization or Payor Copy.

### 4.1 Canonical classifications

#### `USER_TEMPLATE_VALID`

A HER with `USER_FORM_TEMPLATE_GUID` populated is valid when:

- `HER.USER_FORM_TEMPLATE_GUID = PFC.USER_FORM_TEMPLATE_GUID`, and
- its form association is compatible with the selected PFC:
  - `HER.FORM_TEMPLATE_GUID = PFC.FORM_TEMPLATE_GUID`, or
  - `HER.FORM_TEMPLATE_GUID IS NULL`.

#### `FORM_TEMPLATE_VALID`

A HER with no user-template association but a populated form-template association is valid when:

```sql
HER.USER_FORM_TEMPLATE_GUID IS NULL
AND HER.FORM_TEMPLATE_GUID = PFC.FORM_TEMPLATE_GUID
```

#### `BILLING_FORM_VALID`

A HER with both template associations NULL is valid at billing-form level:

```sql
HER.USER_FORM_TEMPLATE_GUID IS NULL
AND HER.FORM_TEMPLATE_GUID IS NULL
```

A template-less HER remains valid even when the selected PFC itself has template GUIDs.

#### `STALE_TEMPLATE_ASSOCIATION`

A populated HER template association that does not apply to the selected PFC is stale/inapplicable for that context.

Stale rows should remain visible in diagnostics. They must not be silently reclassified as valid and must not be copied as though they belonged to the selected PFC.

### 4.2 Template precedence for inherited MatrixCare sources

When resolving a non-payor source HER for a known record type, the established specificity order is:

1. user-template source
2. form-template source
3. billing-form/template-less source

Within the same template specificity, an exact `PAYOR_TYPE_GUID` source is preferred over a NULL `PAYOR_TYPE_GUID` source.

The normal inherited source population is expected to have:

```sql
HER.PAYOR_GUID IS NULL
AND HER.PLAN_GUID IS NULL
AND HER.TYPE_OF_BILL IS NULL
```

If more than one candidate remains at the winning specificity/rank, block as ambiguous rather than selecting arbitrarily.

---

## 5. Canonical payor HER plan-context rule

This rule applies equally to:

- PFC customization
- Payor Copy source resolution
- current/effective payor configuration recognition

### 5.1 No-plan PFC

For a selected PFC where:

```sql
PFC.PLAN_GUID IS NULL
```

eligible payor-specific HER rows must have:

```sql
HER.PLAN_GUID IS NULL
```

A populated HER plan is not part of the no-plan PFC context.

### 5.2 Plan-specific PFC

For a selected PFC where `PFC.PLAN_GUID` is populated, eligible payor-specific HER rows may have either:

```sql
HER.PLAN_GUID = PFC.PLAN_GUID
```

or the historical fallback:

```sql
HER.PLAN_GUID IS NULL
```

A different populated plan is out of scope:

```sql
HER.PLAN_GUID IS NOT NULL
AND HER.PLAN_GUID <> PFC.PLAN_GUID
```

Such rows must not be copied, edited, deleted, or used to determine the selected plan's current configuration.

### 5.3 Exact-plan precedence over NULL fallback

For the same applicable logical HER identity:

1. an exact `HER.PLAN_GUID = selected PFC.PLAN_GUID` candidate wins;
2. a `HER.PLAN_GUID IS NULL` candidate is fallback only when there is no exact-plan winner.

The NULL-plan candidate exists to tolerate historical MatrixCare inconsistencies. It is not the preferred representation for new plan-specific configuration.

If more than one candidate exists at the winning level, block as ambiguous rather than guessing.

### 5.4 Logical HER identity

Do not deduplicate unrelated HER rows merely because they share a payor or record type.

At minimum, identity must preserve:

- payor context
- billing form
- record type
- applicable template context

Rows from incompatible template contexts are not the same logical HER identity.

Any implementation-specific refinement of identity must remain conservative. HEF content must not be used to collapse distinct HERs unless a tested business rule explicitly requires it.

---

## 6. Historical-read / canonical-write model

Production evidence confirms both patterns exist historically:

- payor-specific HERs whose populated `PLAN_GUID` matches the plan associated with the payor's PFC;
- plan-specific PFC configurations where related payor HERs have `PLAN_GUID IS NULL`.

Therefore the tool follows this model:

> **Read historical data permissively; write new data canonically.**

### 6.1 Canonical HER write metadata

Any new or rebuilt payor-specific HER must use:

```text
HER.PAYOR_GUID = selected destination payor
HER.PLAN_GUID  = selected destination PFC.PLAN_GUID
```

For a no-plan destination PFC, the canonical HER plan is NULL.

For a plan-specific destination PFC, the canonical HER plan is that populated PFC plan GUID, even when the source HER was a legacy NULL-plan fallback.

The source HER's `PAYOR_GUID` and `PLAN_GUID` are never blindly copied to the destination.

### 6.2 Other canonical payor metadata

For new/rebuilt payor-specific HERs:

- `PAYOR_TYPE_GUID` comes from `PAYORS.PAYOR_TYPE_GUID` for the selected payor.
- `CARRY_FORWARD_IND` is normalized to NULL where the generic engine requires canonical payor metadata.
- `INCLUDE_RECORD_DATA_ONCLAIM` is normalized to `Y` where the generic engine requires canonical payor metadata.
- insert audit fields use the operation audit user and insert timestamp;
- modification audit fields are NULL on a newly inserted row.

Functional HER attributes are cloned from the selected source/configuration and then modified only by the requested option or copy-context rules.

---

## 7. PFC customization behavior

For each managed record type in a selected PFC:

1. Resolve the exact selected PFC; do not infer it from date or plan label.
2. Resolve the applicable inherited MatrixCare source HER using template specificity and payor-type precedence.
3. Resolve payor-specific current candidates using the canonical plan-context rule:
   - exact selected plan;
   - NULL fallback for a plan-specific PFC;
   - exclude every other populated plan.
4. Apply template applicability.
5. Within the same logical identity, exact-plan candidate wins over NULL fallback.
6. Block if the winning current level is ambiguous.
7. Build the desired HER and full desired HEF set in memory before DML.
8. If a payor-specific HER is created or rebuilt, write the selected PFC's `PLAN_GUID` canonically.
9. Never mutate another populated plan's HER as part of the selected plan's operation.

### 7.1 Legacy NULL fallback mutation safety

For a plan-specific PFC, a NULL-plan HER may historically function as fallback for more than one plan context. Therefore it must not automatically be treated as exclusively owned by the selected plan.

A plan-specific operation must not blindly delete or modify a legacy NULL-plan HER when doing so could alter another plan's effective configuration.

When the selected plan needs to diverge from a NULL fallback, the safe canonical direction is to create or maintain an exact-plan row that shadows the fallback for that plan.

The detailed destructive-normalization policy for shared legacy NULL fallback rows must preserve plan isolation and be covered by explicit local integration tests before implementation.

### 7.2 No-change / remove / rebuild semantics

The generic engine uses these conceptual outcomes:

- `NO_CHANGE`
- `REMOVE_OVERRIDE`
- `REBUILD_OVERRIDE`
- `BLOCKED`

An inherited source that already equals the desired behavior does not require a redundant payor override unless a plan-specific exact row is required to isolate the selected plan from a conflicting legacy NULL fallback.

Any removal logic must be plan-aware and must not use only `PAYOR_GUID + BILLING_FORM_CODE + RECORD_TYPE_CODE` as destructive scope for plan-specific configuration.

---

## 8. Generic HER mandatory invariant

For canonical payor-specific configuration, when the desired HER stored-procedure behavior is not `RETURN_1` (including NULL), `MANDATORY_IND` must be `N`.

Conceptually:

```text
STO_PROC_NAME != RETURN_1  =>  MANDATORY_IND = N
```

An inherited source that violates this invariant must not be silently cloned into a new payor override.

`RETURN_1` configurations may preserve the applicable source mandatory behavior unless a feature-specific rule says otherwise.

Default/inherited behavior should remain exact inheritance when safe rather than creating unnecessary overrides.

---

## 9. HEF cloning and comparison

HER and HEF configuration is treated as a complete configuration set.

When rebuilding or copying a HER:

1. clone the full source HEF set;
2. assign the new parent `ELECTRONIC_REC_GUID` to every cloned HEF;
3. preserve unmanaged HEF attributes;
4. apply only the explicit managed field overlays required by the option;
5. set insert audit fields for all newly inserted HEFs;
6. verify the complete resulting HEF multiset, not only managed fields.

Do not assume a fixed HEF count unless a feature's explicit source contract requires one. Payor Copy must clone every HEF belonging to every copied HER.

Counts must be protected from parent/child multiplication. Aggregate HEF counts before joining when reporting HER-level statistics, or use distinct parent counts explicitly.

---

## 10. Payor Copy

Payor Copy operates between two explicitly selected PFC contexts:

```text
Source:      source payor + source PFC
Destination: destination payor + destination PFC
```

The selected source and destination `PFC_GUID`s are authoritative.

### 10.1 Source HER population

For a plan-specific source PFC, consider payor-owned HERs that satisfy:

```sql
HER.PAYOR_GUID = source payor
AND HER.BILLING_FORM_CODE = source PFC billing form
AND (
    HER.PLAN_GUID = source PFC.PLAN_GUID
    OR HER.PLAN_GUID IS NULL
)
```

For a no-plan source PFC, only `HER.PLAN_GUID IS NULL` qualifies.

Then apply template applicability.

A HER with another populated plan is excluded even if its record type resembles a source row that is being copied.

### 10.2 Exact vs fallback during copy

For the same applicable logical HER identity:

- exact source plan wins;
- NULL-plan source is fallback;
- another populated plan is excluded;
- multiple winners at the same level block as ambiguous.

Do not clone both exact and NULL versions of the same logical identity into duplicate destination configuration.

### 10.3 Generic record-type scope

Payor Copy copies all qualifying payor-defined HER record types. It is not limited to Provider Taxonomy, Service Facility, Value Codes, Remarks, or any other currently recognized UI option.

Unsupported/unfamiliar record types must remain eligible when they satisfy the source PFC's plan and template context.

Every copied HER brings its complete HEF child set.

### 10.4 Destination normalization

Every copied destination HER is canonicalized to:

```text
PAYOR_GUID = destination payor
PLAN_GUID  = destination PFC.PLAN_GUID
PAYOR_TYPE_GUID = destination PAYORS.PAYOR_TYPE_GUID
```

The source plan GUID is not copied.

Example:

```text
Source PFC: Plan A
Source HER X: PLAN_GUID = Plan A
Source HER Y: PLAN_GUID = NULL
Source HER Z: PLAN_GUID = Plan B

Eligible source: X and Y
Excluded source: Z

Destination PFC: Plan C
Copied X: PLAN_GUID = Plan C
Copied Y: PLAN_GUID = Plan C
```

### 10.5 Template associations during copy

Source HER template GUIDs must not be blindly copied.

If **Copy template associations** is enabled:

1. copy the selected source PFC's `FORM_TEMPLATE_GUID` and `USER_FORM_TEMPLATE_GUID` to the selected destination PFC;
2. determine destination HER template associations against that resulting destination PFC context.

If **Copy template associations** is disabled:

1. leave the destination PFC template GUIDs unchanged;
2. determine copied HER template associations against the existing destination PFC context.

Template-less HERs can remain valid in a templated destination context.

Stale source template associations are not copied as valid associations.

### 10.6 `TYPE_OF_BILL`

Payor HERs with populated `TYPE_OF_BILL` must remain visible in diagnostics. They are not assumed to be clean generic copy candidates without an explicit rule establishing their applicability.

Do not silently discard them from investigation output, and do not silently treat them as standard copy rows.

### 10.7 Replacement scope and legacy NULL fallback

Payor Copy is intended as destination replacement for the selected PFC context, not as payor-wide deletion.

At minimum:

- another populated destination plan is never part of the selected destination plan's destructive scope;
- exact destination-plan rows may be replaced for the selected context;
- legacy NULL-plan fallback rows require conservative handling because they can historically affect more than one plan.

Strict destructive replacement and shared legacy NULL fallback can conflict. Before final Payor Copy DML is implemented, local integration tests must establish a safe rule that preserves plan isolation when a destination NULL fallback exists but the copied source does not contain the same logical identity. Do not resolve that case by deleting NULL fallback rows blindly.

---

## 11. Ambiguity policy

The system fails closed when identity or precedence cannot produce one deterministic winner.

Examples that must block rather than guess:

- multiple eligible PFCs without explicit user PFC selection;
- multiple PFC rows sharing a plan when only the plan was supplied rather than an exact PFC;
- multiple inherited source HERs tied at the highest template/payor-type rank;
- multiple exact-plan payor HER candidates for the same logical identity;
- no exact-plan candidate and multiple NULL fallback candidates for the same logical identity.

Ambiguity should be surfaced with enough identifiers/context for diagnosis, but production-facing tools should avoid unnecessary customer data.

---

## 12. Production observations versus canonical behavior

Historical production state is not assumed to be canonical.

Known observations:

- populated payor HER `PLAN_GUID` values exist;
- production examples have been confirmed where a HER plan matches the plan associated with the payor's PFC;
- other historical configurations leave `HER.PLAN_GUID` NULL even when plan-specific PFCs exist;
- therefore NULL-plan payor HERs must be supported as fallback input for plan-specific PFCs.

Canonical behavior going forward is independent of which historical convention was more common:

```text
Read:  exact selected plan + legacy NULL fallback
Reject: other populated plans
Rank:  exact plan over NULL fallback
Write: selected destination PFC.PLAN_GUID
```

Normal development should now be reproducible in the local environment. Production access should be reserved for genuinely unknown MatrixCare schema/behavior questions, not routine test setup.

Do not commit real production payor inventories, customer names, screenshots, or large production exports as fixtures.

---

## 13. Local Oracle synthetic test data

The local Oracle test database should contain deterministic synthetic MatrixCare-shaped data. Tests should create or reset reserved synthetic rows automatically rather than requiring manual Toad setup.

Seed at least these topologies:

| Scenario | PFC context | Payor HER state | Required behavior |
|---|---|---|---|
| No-plan basic | No plan | NULL-plan HER | NULL is the only valid payor plan context |
| Canonical plan | Plan A | Plan A HER | Exact-plan winner |
| Historical fallback | Plan A | NULL HER | NULL fallback is usable |
| Other plan isolation | Plan A | Plan B HER | Plan B excluded |
| Exact + fallback | Plan A | Plan A + NULL same identity | Plan A wins |
| Multi-plan | Plan A + Plan B | Plan A + Plan B + NULL | Selected plan isolated; NULL only fallback |
| Exact ambiguity | Plan A | 2 exact same-identity candidates | Block |
| Fallback ambiguity | Plan A | 2 NULL same-identity candidates | Block when no exact winner |
| Template-less | templated PFC | HER templates both NULL | Billing-form valid |
| Stale template | selected PFC | incompatible populated HER template | Visible, not applicable |
| Shared plan GUID | multiple PFCs | same populated PFC plan | PFC_GUID selection required |
| Generic record type | selected PFC | unrecognized HER + HEFs | Payor Copy includes it |
| TYPE_OF_BILL diagnostic | selected PFC | HER TYPE_OF_BILL populated | Visible; not silently standard-copy eligible |
| Complete HEF clone | selected PFC | HER with unmanaged HEFs | All HEFs preserved/cloned |

Test data must use synthetic identifiers only.

### 13.1 Fixture lifecycle

Preferred test behavior:

1. delete/reset only reserved synthetic fixture identifiers;
2. insert `PAYORS` rows;
3. insert eligible and intentionally ineligible `PFC` rows;
4. insert HER rows for the required plan/template topologies;
5. insert complete HEF child sets;
6. run integration tests;
7. clean up or deterministically reset on the next run.

Module/session-scoped seeding is acceptable when it materially improves test performance, provided tests remain deterministic and isolated from developer data.

---

## 14. Preview, apply, and verification safety

Production validation harnesses are not deployment scripts.

### 14.1 Read-only harnesses

A `READ_ONLY` production script:

- uses MatrixCare-owned objects only;
- performs no DML or DDL;
- does not commit;
- does not lock with `FOR UPDATE`;
- does not depend on tool-owned packages/tables/types;
- does not use `&` substitution variables;
- keeps real production identifiers only in an unsaved working copy.

### 14.2 Rollback-only apply harnesses

A `ROLLBACK_ONLY_APPLY` harness must:

- run in a fresh dedicated session;
- re-resolve/lock the state before temporary DML;
- reject a stale Preview/state hash before DML;
- apply the complete target atomically;
- verify temporary canonical state;
- roll back to the savepoint;
- verify restoration;
- finish with a full rollback;
- have no COMMIT path.

### 14.3 Application preview/apply invariant

The application should build a complete desired state before mutation and should not apply a stale preview. Missing, ambiguous, or changed state between preview and apply must block or require a fresh preview rather than silently changing the target.

---

## 15. Counting and reporting rules

Reports must distinguish between:

- a distinct HER row;
- a PFC/HER relationship pair;
- a HEF child row.

Do not report PFC×HER relationship counts as though they were unique HER counts.

Do not multiply parent HER counts by joining directly to HEF without pre-aggregation or distinct-parent counting.

Stale template rows, other-plan rows, unknown record types, and populated `TYPE_OF_BILL` rows should remain visible when a diagnostic report is intended to explain production topology.

Diagnostic labels should be observational where the report is collecting evidence; canonical business labels belong in engine behavior.

---

## 16. Rules that older implementation code must not preserve merely for compatibility

The following historical implementation patterns are not canonical if they conflict with this document:

- selecting a PFC by newest `CPD_START_DATE`;
- treating `PLAN_GUID` as irrelevant to payor-specific HER ownership;
- destructive cleanup scoped only by `PAYOR_GUID + BILLING_FORM_CODE + RECORD_TYPE_CODE` across all plans;
- copying the source HER's plan GUID to a different destination plan;
- excluding legacy NULL-plan HERs from a plan-specific source context;
- including another populated plan as source fallback;
- blindly copying source HER template GUIDs during Payor Copy;
- limiting Payor Copy to tool-recognized record types;
- cloning only managed HEFs instead of the complete child set;
- silently choosing among tied source/current candidates.

---

## 17. Implementation order

The recommended implementation sequence is:

1. make this document and the schema/reference capture output the durable source of truth;
2. seed deterministic local Oracle fixtures for plan and template topologies;
3. update the shared PFC customization engine to the canonical plan-context rule;
4. update feature-specific integration tests and standalone production harnesses to the same rule;
5. verify plan isolation and legacy NULL fallback behavior locally;
6. implement Payor Copy on the same shared resolution behavior;
7. add Payor Copy-specific template-association and destructive-replacement tests;
8. use production only when a new MatrixCare fact cannot be established from the documented schema and local fixtures.

Payor Copy should not implement an independent version of plan resolution. Both customization and copy must consume the same canonical semantics.

---

## 18. Explicitly unresolved implementation edge

One edge remains intentionally unresolved at the DML-policy level:

> **How should a plan-specific destructive operation suppress or replace a shared legacy `HER.PLAN_GUID IS NULL` fallback without changing the effective configuration of other plans?**

The canonical constraints are already settled:

- NULL is readable fallback for a plan-specific PFC;
- exact selected plan wins;
- other populated plans are out of scope;
- new writes use the exact selected PFC plan;
- a plan-specific operation must preserve plan isolation;
- shared NULL fallback must not be deleted blindly.

The final DML strategy for this edge should be chosen using synthetic multi-plan fixtures before Payor Copy persistence is implemented. No additional production evidence is required unless local design work uncovers a genuinely unknown MatrixCare behavior.

---

## 19. Compact canonical decision table

| Question | Canonical answer |
|---|---|
| What selects a configuration context? | Exact eligible `PFC_GUID` |
| Is `CPD_START_DATE` eligibility or selection logic? | No |
| What does NULL PFC plan mean? | No plan |
| Plan-specific payor HER candidates? | Exact selected plan + NULL fallback |
| No-plan payor HER candidates? | NULL plan only |
| Other populated plan? | Excluded |
| Exact and NULL same logical identity? | Exact wins |
| Multiple winners at winning level? | Block |
| New/rebuilt plan-specific HER plan? | Selected PFC `PLAN_GUID` |
| New/rebuilt no-plan HER plan? | NULL |
| New HER payor type? | `PAYORS.PAYOR_TYPE_GUID` |
| Template-less HER valid against templated PFC? | Yes |
| Stale populated template association? | Visible diagnostically; not applicable |
| Unknown HER record type in Payor Copy? | Include when otherwise qualifying |
| HEFs copied? | Complete child set |
| Source template GUIDs blindly copied in Payor Copy? | No |
| Copy another populated source plan? | No |
| Delete another populated destination plan? | No |
| Blindly delete shared legacy NULL fallback? | No |
| Guess between PFCs or tied HERs? | Never |


