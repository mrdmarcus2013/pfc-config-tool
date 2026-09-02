/*
 * Remove only this POC's unmistakably synthetic seed data.
 * This is a data reset, not a schema teardown. Re-run 02 and 03 afterward.
 */
SET DEFINE OFF

/* Remove Apply-created rows for this POC's synthetic payors regardless of
 * which synthetic audit user performed the local test operation. */
DELETE FROM hcfa_electronic_fields f
WHERE EXISTS (
    SELECT 1
    FROM hcfa_electronic_records h
    JOIN payors p ON p.payor_guid = h.payor_guid
    WHERE h.electronic_rec_guid = f.electronic_rec_guid
      AND p.rec_ent_user = '90000000-0000-0000-0000-000000000001'
);

DELETE FROM hcfa_electronic_records h
WHERE EXISTS (
    SELECT 1
    FROM payors p
    WHERE p.payor_guid = h.payor_guid
      AND p.rec_ent_user = '90000000-0000-0000-0000-000000000001'
);

DELETE FROM hcfa_electronic_fields
WHERE rec_ent_user = '90000000-0000-0000-0000-000000000001';

DELETE FROM hcfa_electronic_records
WHERE rec_ent_user = '90000000-0000-0000-0000-000000000001';

DELETE FROM linking_form_lu
WHERE billing_form_code = 'UB04'
  AND phys_form_field_num = '81'
  AND record_type_code = 'B2000A0030PRV080'
  AND field_number IN ('01', '02', '03');

DELETE FROM pfc
WHERE rec_ent_user = '90000000-0000-0000-0000-000000000001';

DELETE FROM pfc_config_payor_context c
WHERE EXISTS (
    SELECT 1
    FROM payors p
    WHERE p.payor_guid = c.payor_guid
      AND p.rec_ent_user = '90000000-0000-0000-0000-000000000001'
);

DELETE FROM payors
WHERE rec_ent_user = '90000000-0000-0000-0000-000000000001';

COMMIT;
