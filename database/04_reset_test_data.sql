/*
 * Remove only this POC's unmistakably synthetic seed data.
 * This is a data reset, not a schema teardown. Re-run 02 and 03 afterward.
 */
SET DEFINE OFF

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

DELETE FROM payors
WHERE rec_ent_user = '90000000-0000-0000-0000-000000000001';

COMMIT;
