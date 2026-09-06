import test from "node:test";
import assert from "node:assert/strict";
import { CLAIM_SECTION_LAYOUT, baseFieldNumber } from "../.test-build/app/claim-section-layout.js";
import { CLAIM_FIELD_CATALOG } from "../.test-build/data/claim-field-catalog.js";

test("claim layout places every catalog field exactly once and preserves catalog order", () => {
  const laidOutFields = CLAIM_SECTION_LAYOUT.flatMap(section => section.groups.flatMap(group =>
    CLAIM_FIELD_CATALOG.filter(field => field.section === section.name
      && baseFieldNumber(field) >= group.from && baseFieldNumber(field) <= group.through)));
  assert.deepEqual(laidOutFields.map(field => field.id), CLAIM_FIELD_CATALOG.map(field => field.id));
  assert.equal(new Set(laidOutFields.map(field => field.id)).size, CLAIM_FIELD_CATALOG.length);
});
