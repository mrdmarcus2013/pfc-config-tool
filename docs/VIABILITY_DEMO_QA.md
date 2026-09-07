# PFC viability demonstration: questions and answers

Prepared September 7, 2026, for the accepted application checkpoint `3d90904`.
These answers describe the working demonstration. Production work is deferred.
The database contains synthetic data modeled on known MatrixCare schema and
configuration behavior, with explicitly identified additions for the tool.

## Developer questions

**1. Line of Business is not captured on PFC today. Where is it handled here?**

The tool stores it in a separate local Oracle table,
`PFC_CONFIG_PAYOR_CONTEXT`, keyed by `PAYOR_GUID`. It holds `HOME_HEALTH` or
`HOSPICE`, plus insert/modification dates and audit users. No LOB column was
added to PFC. One saved value applies to the payor and all its plans. This is
tool-owned application metadata, not a claim that MatrixCare already stores it.
Oracle reads and validates the saved value; it is not just a browser filter.

**2. What happens when a payor has no Line of Business?**

The tool reports it as undefined and requires the user to select and save it
before editing claim-field settings. The initial Save inserts the metadata row
and preserves existing HER/HEF configuration. The tool does not guess LOB from
the plan or template. Value Codes uses the saved LOB to validate its available
capabilities, and Copy requires the source and destination values to match.

**3. What happens when someone changes an existing Line of Business?**

The user previews and confirms the change. Oracle removes the payor-owned
overrides for the registered managed targets across all plans, then updates LOB
in the same transaction. Unregistered targets remain. The operation does not
change the PFC's form-template or user-template associations, so changing LOB
does not itself select a different template hierarchy.

**4. Is this an exact copy of the MatrixCare database?**

No. It is a local Oracle model of the known tables, relationships and
configuration rules needed for these workflows. Unknown constraints, indexes
and triggers are not reproduced. The data is entirely synthetic. LOB storage,
the local plan-ownership registry, template-name catalogs and the tool's Oracle
packages are supporting additions; they should not be presented as existing
MatrixCare objects. The demonstration establishes behavior within this model.

**5. What roles do PFC, HER and HEF play?**

PFC identifies the payor/plan billing configuration and its form-template and
user-form-template associations. HER (`HCFA_ELECTRONIC_RECORDS`) holds the
record-level configuration. HEF (`HCFA_ELECTRONIC_FIELDS`) holds the individual
field definitions linked to an HER. Ordinary field edits primarily manage
HER/HEF overrides. Copy also updates the destination PFC's two template
associations; there is no additional, separate "PFC template" being copied.

**6. How do you ensure a plan belongs to only one payor?**

The local `PFC_CONFIG_PLANS` registry records one owner per plan. Ownership
triggers and composite foreign keys enforce the relationship, and Oracle
validates it during resolution. The UI lists only the selected payor's plans.
This registry is a tool-owned model of the required ownership rule.

**7. Which PFC is authoritative when several exist for the same payor/plan?**

Oracle considers the exact selected payor/plan scope, electronic configurations
with `CPD_END_DATE > SYSDATE` and no `TYPE_OF_BILL`, then chooses the newest
`REC_ENT_DATE`. Tied newest dates or missing eligible entry dates block the
operation. `CPD_START_DATE` is not a tie-breaker. A selected plan without an
eligible PFC does not silently fall back to a no-plan PFC.

**8. How does inheritance work, and why are some overrides removed?**

Precedence is **Payor Plan > Payor Defined > User Template > Form Template >
Billing Form**, subject to template applicability and payor type. An ordinary
explicit edit starts with the complete inherited HER and all its HEFs, changes
only managed values, and applies the documented safety rules. If the result
already equals inheritance, the engine avoids or removes an unnecessary
override. Cleanup stays within the selected editing scope and managed targets;
parent and sibling-plan records are preserved during a plan edit.

**9. Which logic runs in React, Python and Oracle?**

React displays current settings and collects proposals and confirmations.
FastAPI validates requests and responses, calls Oracle, translates errors and
controls commit/rollback. Oracle resolves ownership and hierarchy, builds and
compares desired settings, calculates preview hashes and performs mutations.
The application packages are part of this tool. For example, Oracle now returns
structured effective and inherited Value Code flags; the UI does not infer
enabled capabilities from a text label.

**10. What prevents a stale preview or a partially saved configuration?**

Apply locks and rereads the relevant state and checks the supplied Preview hash
before changing target records. A changed state rejects the old Preview.
Related HER/HEF changes are transactional, and failures roll them back. The API
validates the response before committing. Copy deliberately uses broader
write-excluding locks with `NOWAIT`; a conflicting operation can receive a busy
message. The demo does not establish performance under heavy concurrent use.

**11. How would a developer add another configurable field?**

Define its verified record/field targets and permitted changes, register the
option, expose its plain-language API/UI capability, and test Current, Preview
and Apply through the shared engine. Structured input can use an adapter like
Value Codes or Remarks. Managed-target registration also determines LOB reset
scope. A visible claim box or a newly added database record does not
automatically become an editable feature.

Developer references: [local schema](../database/01_schema.sql),
[database model and limitations](../database/README.md),
[engine rules](CLAIM_CONFIGURATION_ENGINE_RULES.md),
[plan ownership and hierarchy](PAYOR_PLAN_CONFIGURATION.md),
[LOB implementation](../database/packages/pfc_line_of_business.pkb).

## Project manager questions

**12. What is the project demonstrating?**

It demonstrates that selected claim-configuration tasks can be presented as
plain-language choices while Oracle resolves the hierarchy and performs
controlled database changes. The core examples are payor/plan editing,
inheritance, reviewed changes and copying a working configuration to another
eligible payor.

**13. Which capabilities are actually implemented?**

Provider Taxonomy, Service Facility, Value Codes and Remarks are editable.
The tool also includes linked payor/plan selectors, payor-wide LOB assignment
and change, and Copy Payor Settings. Value Codes supports different Home Health
and Hospice choices. The broader claim layout includes boxes whose editing
capabilities have not been implemented. The configured billing-form scope is
`837I_5010`.

**14. Is this a visual mockup, or does Apply change a database?**

It performs real reads and writes against the local Oracle database. A successful
Apply commits changes to synthetic configuration rows, which subsequent reads
can retrieve. Preview leaves saved configuration unchanged. Automated mutation
tests use rollback so their temporary changes do not replace the user's saved
demo settings.

**15. What evidence supports the demonstration?**

The accepted checkpoint passed 136 frontend tests, 527 Python tests and the
frontend build/typecheck; 39 environment-gated Python tests were skipped.
Comparison also preserved 706 read/preview cases and 35 rollback-only Apply
cases, excluding only the intentionally added Value Codes Current metadata.
The user reported sufficient successful manual browser testing for this demo.
Agent automation did not establish full mounted-browser or screen-reader
coverage. These results support the tested configuration workflows.

**16. What business benefit has been measured?**

The tool demonstrates mechanisms intended to reduce repeated setup, manual
database work and uncertainty about inherited settings. It has not measured a
percentage improvement in setup time, support workload, rework or payment
speed. Those would require a separate comparison with the current process.

**17. Does copying a successful payor guarantee successful claims or payment?**

No. Copy checks configuration equivalence within its supported scope, including
the inherited hierarchy and approved safety adjustments. It does not generate,
submit or adjudicate claims, or verify patient, provider, contract and claim
data. The demonstrated outcome is matching configuration behavior, not a
payment guarantee.

**18. Which assumptions should reviewers understand during the demonstration?**

The tool assumes one LOB per payor, so it does not model different LOB values
for that payor's individual plans. Copy targets a whole existing payor, clears
destination plan overrides, and requires matching LOB and billing form. The
Remarks maximum of 100 characters is a provisional tool limit. These are
explicit current choices and useful subjects for stakeholder feedback.

Project references: [accepted version and verification](REFACTOR_STAGES.md),
[implemented UI capabilities](../frontend/src/data/configuration-capabilities.ts),
[Remarks and API behavior](../README.md), [Copy contract](PFC_COPY_RULES.md).

## End-user questions

**19. Am I changing the payor or just one plan?**

Choose **Payor-level settings** to edit the shared payor level. Choose a named
plan to edit only that plan's overrides. A payor-level change can affect plans
that inherit that setting; their own applicable overrides retain precedence.
Changing the selected payor resets the Plan selection to Payor-level settings.

**20. Does Default mean the setting is disabled?**

No. Default, or **Use inherited settings**, removes the customization at the
level being edited and uses the applicable parent configuration. That parent
may enable or disable the capability. A plan can inherit its payor's settings;
the template and billing-form levels supply the remaining inheritance.

**21. Why are CBSA and FIPS checked but unavailable to click?**

They are enabled through inherited settings. Choose **Customize for this
payor** or **Customize for this plan** to edit them; the checkboxes start with
the effective values. FIPS requires CBSA. The current Value Codes editor does
not offer an explicit all-capabilities-Off override: empty custom selections
cannot be previewed, and choosing inheritance uses whatever the parent supplies.

**22. Why must I Preview before Apply?**

Preview lets you review a proposed change without saving it. Apply verifies
that the relevant configuration still matches that review. If it has changed,
the tool rejects the stale Preview and requires another review. Changing your
proposal also invalidates its previous Preview.

**23. What exactly does Copy Payor Settings change?**

It combines the source payor's settings with those of the selected source plan,
with that plan winning where both define the same logical record. It applies
that combined set as destination payor-level settings, removes destination-only
settings in scope, and clears destination plan overrides. Every current
authoritative destination PFC, both no-plan and plan-specific, adopts the
source PFC's respective form-template and user-template associations. Historical
or non-winning PFCs are left alone. Preview shows the copy, keep, removal and
template-association changes before confirmation.

**24. Does the source keep its settings, and are the copied records separate?**

Yes. Source records stay unchanged. When a new destination HER is needed, it
gets a new identifier, the destination `PAYOR_GUID`, and `PLAN_GUID = NULL`.
Its copied HEFs point to that new parent. A canonical matching destination
record can be kept. The source and destination therefore retain their own
records; Copy does not transfer ownership away from the source.

**25. Why is a destination missing from the Copy dropdown?**

Only eligible payors from the synthetic demo catalog appear. A destination must
be a different payor with matching billing form and LOB, an eligible no-plan
PFC, and valid affected plan contexts. Oracle also checks that the proposed
complete configuration can match the source safely. Ambiguous or unsupported
states can exclude it. An invalid source produces an error; an empty list means
that no catalog destination qualifies for that valid source.

**26. What happens to settings the screen cannot edit individually?**

Ordinary field editing retains the source's unmanaged field details. Copy
includes qualifying configuration record types beyond the four editable areas,
and can remove destination-only settings and plan overrides in its supported
scope. It does not silently discard unsupported configurations to make a copy
pass. Review the Copy details, especially the settings being removed.

**27. Can I undo a saved change by choosing Default?**

There is no one-click historical Undo in this demo. Cancel before Apply leaves
saved settings unchanged. After a successful Apply, you can make another
reviewed change. Default uses the current inherited configuration; it does not
recover an earlier custom configuration or reverse a completed Copy.

**28. Does Copy keep the two payors synchronized afterward?**

It is a one-time operation. Later edits to source payor/plan overrides do not
automatically update the destination. Both payors can reference the same shared
form and user templates after Copy, so later changes to applicable shared
templates can affect inherited settings on both. The copy is not a frozen
snapshot of all future template behavior.

**29. Can I create a payor, plan or PFC, or copy into just one destination plan?**

Those operations are not included. The tool selects existing configured payors
and owned plans. Copy can read from a selected source plan, but its destination
is the payor as a whole; it does not offer a destination-plan selector.

**30. Is Tier 2 a different tool?**

It is the same application with additional collapsed Technical Details enabled
through the local `VITE_ENABLE_TECHNICAL_DETAILS` setting. Those details expose
configuration identifiers and diagnostic information. The setting is a display
mode, not an authenticated permission role. The demonstration's audit identity
comes from its development launch context.

End-user references: [frontend guide](../frontend/README.md),
[payor and plan behavior](PAYOR_PLAN_CONFIGURATION.md),
[Copy rules](PFC_COPY_RULES.md),
[Value Codes inheritance](SYNTHETIC_CONFIGURATION_HIERARCHY.md).
