# Claim Configuration Engine Rules

## Scope

These rules apply to every MatrixCare HER/HEF configuration managed by the PFC
tool unless a more specific approved rule explicitly overrides them. The
generic Oracle configuration engine is authoritative for cross-feature rules.

## Payor plan scope

[Payor plan configuration](PAYOR_PLAN_CONFIGURATION.md) defines the approved
ownership and PFC selection rules. Effective precedence is Payor Plan, Payor
Defined, User Template, Form Template, Billing Form. Default means zero overrides
at the selected editing level. Plan Default preserves the null-plan payor parent.
All counts, hashes, locks, deletes and verification must use exact editing scope.

## HER mandatory invariant

If `HER.STO_PROC_NAME` is anything other than `RETURN_1`, including `NULL`,
`HER.MANDATORY_IND` must be `N`. Conditional and always-off records cannot
safely remain mandatory because MatrixCare may require a record that the
configured procedure does not produce.

`RETURN_1` does not imply `MANDATORY_IND = 'Y'`. For `RETURN_1`, the applicable
source-derived value is preserved unless another approved rule governs it.

A HER is safe when its stored procedure is `RETURN_1` or its mandatory
indicator is `N`. Null comparisons must fail safely.

## Explicit desired-state normalization

For an explicit configuration, the engine must:

1. Clone the complete authoritative source.
2. Apply feature-specific HER overlays.
3. Apply feature-specific HEF overlays.
4. Apply all global HER/HEF safety invariants.
5. Compare the normalized desired functional state with the source.
6. Use the minimal-override algorithm.

The mandatory invariant therefore changes only `MANDATORY_IND` to `N` when the
desired stored procedure is not `RETURN_1`. It does not normalize unrelated HER
columns.

## DEFAULT exception

Default means exact inheritance of the complete authoritative MatrixCare
source with zero canonical overrides at the selected level. The tool must not normalize an
unsafe inherited source or create an override merely to repair it.

If the inherited source violates a global safety invariant, Default is blocked.
The error must identify the inherited source as invalid and require correction
of the inherited payor, template or billing-form source. No repair DML is permitted on a Default
path.

## Current override safety

An unsafe existing payor override is noncanonical. A valid explicit selection
may rebuild it into a safe canonical override. Default may remove an override
only when the inherited source itself is safe; otherwise Default is blocked.

## Source hierarchy

The authoritative source is never another payor's configuration. Plan editing
first inherits an applicable same-payor, null-plan HER. Otherwise, and for payor
editing, resolution uses a non-payor, null-plan, null-type-of-bill HER and ranks:

1. Matching user template.
2. Matching form template.
3. Null-template billing-form source.

Within a level, the exact payor type outranks a null payor type. Missing or tied
best sources fail safely. Full production constraints remain authoritative in
[PRODUCTION_DATABASE_BOUNDARY.md](PRODUCTION_DATABASE_BOUNDARY.md).

## Minimal overrides

- `NO_CHANGE`: the safe inherited source already supplies the request with no
  cleanup, or one canonical override already equals the explicit desired state.
- `REMOVE_OVERRIDE`: the desired state equals a safe source and payor overrides
  exist in cleanup scope.
- `REBUILD_OVERRIDE`: explicit desired state differs from source and current
  payor state is absent, stale, duplicated, unsafe, or otherwise noncanonical.

## Complete cloning

Every source HEF is cloned for an override. Only explicitly managed overlays
may change; all unmanaged HEFs are preserved exactly.

## Paired-value HEF invariant

For managed fields only, setting `STO_PROC_NAME` clears `HARD_CODED_DATA`, and
setting `HARD_CODED_DATA` clears `STO_PROC_NAME`. This paired-value rule must not
globally normalize unmanaged HEFs.

## Adding future global rules

Future cross-feature HER/HEF invariants must be implemented in the generic
engine, documented here, and reproduced in standalone production harnesses and
functional regression tests. Comparisons, deterministic hashes, canonical
verification, and rollback restoration must include every affected business
attribute.
