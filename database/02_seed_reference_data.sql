/* Synthetic reference data for the Oracle POC. Run after 01_schema.sql. */
SET DEFINE OFF

INSERT INTO linking_form_lu (
    billing_form_code, phys_form_field_num, line_num, loop_id,
    field_name, field_number, record_type_code, order_num,
    mandatory_ind, dependency_loop, field_name_desc
) VALUES (
    'UB04', '81', 1, 'PRV',
    'PRV01', '01', 'B2000A0030PRV080', 1,
    'Y', NULL, 'Synthetic provider code qualifier'
);

INSERT INTO linking_form_lu (
    billing_form_code, phys_form_field_num, line_num, loop_id,
    field_name, field_number, record_type_code, order_num,
    mandatory_ind, dependency_loop, field_name_desc
) VALUES (
    'UB04', '81', 1, 'PRV',
    'PRV02', '02', 'B2000A0030PRV080', 2,
    'Y', NULL, 'Synthetic taxonomy qualifier'
);

INSERT INTO linking_form_lu (
    billing_form_code, phys_form_field_num, line_num, loop_id,
    field_name, field_number, record_type_code, order_num,
    mandatory_ind, dependency_loop, field_name_desc
) VALUES (
    'UB04', '81', 1, 'PRV',
    'PRV03', '03', 'B2000A0030PRV080', 3,
    'Y', NULL, 'Synthetic provider taxonomy value'
);

/* Billing-form-level generic PRV clone source. */
INSERT INTO hcfa_electronic_records (
    electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
    record_name, record_type_code, record_size, mandatory_ind,
    req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
    type_of_bill, detail_ind, max_number, invoice_ind,
    form_template_guid, carry_forward_ind, max_carry_forward,
    sto_proc_name, user_form_template_guid, notes,
    rec_ent_date, rec_ent_user, include_record_data_onclaim
) VALUES (
    '30000000-0000-0000-0000-000000000001', 'PRV', 'Y', 'UB04',
    'Synthetic Generic Provider', 'B2000A0030PRV080', 80, 'Y',
    'Y', NULL, NULL, NULL,
    NULL, 'N', '1', 'N',
    NULL, 'N', 0,
    'RETURN_0', NULL, 'Synthetic billing-form-level PRV source',
    DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', 'N'
);

/* Form-template-specific source for PAYOR_E. */
INSERT INTO hcfa_electronic_records (
    electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
    record_name, record_type_code, record_size, mandatory_ind,
    req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
    type_of_bill, detail_ind, max_number, invoice_ind,
    form_template_guid, carry_forward_ind, max_carry_forward,
    sto_proc_name, user_form_template_guid, notes,
    rec_ent_date, rec_ent_user
) VALUES (
    '30000000-0000-0000-0000-0000000000E1', 'PRV', 'Y', 'UB04',
    'Synthetic Form Template Provider', 'B2000A0030PRV080', 80, 'Y',
    'Y', NULL, NULL, NULL,
    NULL, 'N', '1', 'N',
    '40000000-0000-0000-0000-0000000000E1', 'N', 0,
    'RETURN_1', NULL, 'Synthetic form-template PRV source',
    DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
);

/* User-template-specific source for PAYOR_F. */
INSERT INTO hcfa_electronic_records (
    electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
    record_name, record_type_code, record_size, mandatory_ind,
    req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
    type_of_bill, detail_ind, max_number, invoice_ind,
    form_template_guid, carry_forward_ind, max_carry_forward,
    sto_proc_name, user_form_template_guid, notes,
    rec_ent_date, rec_ent_user
) VALUES (
    '30000000-0000-0000-0000-0000000000F1', 'PRV', 'Y', 'UB04',
    'Synthetic User Template Provider', 'B2000A0030PRV080', 80, 'Y',
    'Y', NULL, NULL, NULL,
    NULL, 'N', '1', 'N',
    '40000000-0000-0000-0000-0000000000F1', 'N', 0,
    'RETURN_1', '50000000-0000-0000-0000-0000000000F1',
    'Synthetic user-template PRV source',
    DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
);

/* Each generic source gets the same complete, harmless four-field PRV set. */
INSERT ALL
    INTO hcfa_electronic_fields (
        field_number, electronic_rec_guid, field_name, record_type_code,
        sto_proc_name, pic, field_spec, position_from, position_thru,
        field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
        repeats, detail_ind, occurs_next, hard_coded_data, field_format,
        caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user
    ) VALUES (
        '01', '30000000-0000-0000-0000-000000000001',
        'PRV01', 'B2000A0030PRV080', NULL, 'X(3)', 'A', 1, 3,
        'Synthetic provider code qualifier', 'Y', 'Y', 1,
        1, 'N', '02', 'BI', NULL, 'Y', 'Y',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
    )
    INTO hcfa_electronic_fields (
        field_number, electronic_rec_guid, field_name, record_type_code,
        sto_proc_name, pic, field_spec, position_from, position_thru,
        field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
        repeats, detail_ind, occurs_next, hard_coded_data, field_format,
        caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user
    ) VALUES (
        '02', '30000000-0000-0000-0000-000000000001',
        'PRV02', 'B2000A0030PRV080', NULL, 'X(3)', 'A', 4, 6,
        'Synthetic taxonomy qualifier', 'Y', 'Y', 2,
        1, 'N', '03', 'PXC', NULL, 'Y', 'Y',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
    )
    INTO hcfa_electronic_fields (
        field_number, electronic_rec_guid, field_name, record_type_code,
        sto_proc_name, pic, field_spec, position_from, position_thru,
        field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
        repeats, detail_ind, occurs_next, hard_coded_data, field_format,
        caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user
    ) VALUES (
        '03', '30000000-0000-0000-0000-000000000001',
        'PRV03', 'B2000A0030PRV080', 'G_PROVIDER_TAXONOMY_CODE',
        'X(10)', 'A', 7, 16,
        'Synthetic provider taxonomy value', 'Y', 'Y', 3,
        1, 'N', '04', NULL, NULL, 'Y', 'Y',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
    )
    INTO hcfa_electronic_fields (
        field_number, electronic_rec_guid, field_name, record_type_code,
        sto_proc_name, pic, field_spec, position_from, position_thru,
        field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
        repeats, detail_ind, occurs_next, hard_coded_data, field_format,
        caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user
    ) VALUES (
        '04', '30000000-0000-0000-0000-000000000001',
        'PRV04', 'B2000A0030PRV080', 'G_SYNTHETIC_PROVIDER_AUX',
        'X(10)', 'A', 17, 26,
        'Synthetic unmanaged provider value', 'N', 'Y', 4,
        1, 'N', NULL, NULL, NULL, 'Y', 'N',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
    )
SELECT 1 FROM dual;

INSERT INTO hcfa_electronic_fields (
    field_number, electronic_rec_guid, field_name, record_type_code,
    sto_proc_name, pic, field_spec, position_from, position_thru,
    field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
    repeats, detail_ind, occurs_next, hard_coded_data, field_format,
    caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user,
    rec_mod_date, rec_mod_user, include_data_onclaim
)
SELECT
    field_number,
    '30000000-0000-0000-0000-0000000000E1',
    field_name,
    record_type_code,
    sto_proc_name,
    pic,
    field_spec,
    position_from,
    position_thru,
    field_name_desc,
    mandatory_ind,
    must_fit_length_ind,
    order_num,
    repeats,
    detail_ind,
    occurs_next,
    hard_coded_data,
    field_format,
    caps_ind,
    required_subelement_ind,
    rec_ent_date,
    rec_ent_user,
    rec_mod_date,
    rec_mod_user,
    include_data_onclaim
FROM hcfa_electronic_fields
WHERE electronic_rec_guid = '30000000-0000-0000-0000-000000000001';

INSERT INTO hcfa_electronic_fields (
    field_number, electronic_rec_guid, field_name, record_type_code,
    sto_proc_name, pic, field_spec, position_from, position_thru,
    field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
    repeats, detail_ind, occurs_next, hard_coded_data, field_format,
    caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user,
    rec_mod_date, rec_mod_user, include_data_onclaim
)
SELECT
    field_number,
    '30000000-0000-0000-0000-0000000000F1',
    field_name,
    record_type_code,
    sto_proc_name,
    pic,
    field_spec,
    position_from,
    position_thru,
    field_name_desc,
    mandatory_ind,
    must_fit_length_ind,
    order_num,
    repeats,
    detail_ind,
    occurs_next,
    hard_coded_data,
    field_format,
    caps_ind,
    required_subelement_ind,
    rec_ent_date,
    rec_ent_user,
    rec_mod_date,
    rec_mod_user,
    include_data_onclaim
FROM hcfa_electronic_fields
WHERE electronic_rec_guid = '30000000-0000-0000-0000-000000000001';

/* Billing-form-level non-payor sources for the three Service Facility targets. */
INSERT ALL
    INTO hcfa_electronic_records (
        electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
        record_name, record_type_code, record_size, mandatory_ind,
        req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
        type_of_bill, detail_ind, max_number, invoice_ind,
        form_template_guid, carry_forward_ind, max_carry_forward,
        sto_proc_name, user_form_template_guid, notes,
        rec_ent_date, rec_ent_user, include_record_data_onclaim
    ) VALUES (
        '31000000-0000-0000-0000-000000000001', '2310E', 'Y', 'UB04',
        'Synthetic Service Facility NM1', 'D2310E2500NM1343', 80, 'Y',
        'Y', NULL, NULL, NULL, NULL, 'N', '1', 'N', NULL, 'N', 0,
        'RETURN_0', NULL, 'Synthetic billing-form NM1 source',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', 'N'
    )
    INTO hcfa_electronic_records (
        electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
        record_name, record_type_code, record_size, mandatory_ind,
        req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
        type_of_bill, detail_ind, max_number, invoice_ind,
        form_template_guid, carry_forward_ind, max_carry_forward,
        sto_proc_name, user_form_template_guid, notes,
        rec_ent_date, rec_ent_user, include_record_data_onclaim
    ) VALUES (
        '31000000-0000-0000-0000-000000000002', '2310E', 'Y', 'UB04',
        'Synthetic Service Facility N3', 'D2310E2650N3346', 80, 'Y',
        'Y', NULL, NULL, NULL, NULL, 'N', '1', 'N', NULL, 'N', 0,
        'RETURN_0', NULL, 'Synthetic billing-form N3 source',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', 'N'
    )
    INTO hcfa_electronic_records (
        electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
        record_name, record_type_code, record_size, mandatory_ind,
        req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
        type_of_bill, detail_ind, max_number, invoice_ind,
        form_template_guid, carry_forward_ind, max_carry_forward,
        sto_proc_name, user_form_template_guid, notes,
        rec_ent_date, rec_ent_user, include_record_data_onclaim
    ) VALUES (
        '31000000-0000-0000-0000-000000000003', '2310E', 'Y', 'UB04',
        'Synthetic Service Facility N4', 'D2310E2700N4347', 80, 'Y',
        'Y', NULL, NULL, NULL, NULL, 'N', '1', 'N', NULL, 'N', 0,
        'RETURN_0', NULL, 'Synthetic billing-form N4 source',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', 'N'
    )
SELECT 1 FROM dual;

INSERT ALL
    INTO hcfa_electronic_fields (
        field_number, electronic_rec_guid, field_name, record_type_code,
        sto_proc_name, pic, field_spec, position_from, position_thru,
        field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
        repeats, detail_ind, occurs_next, hard_coded_data, field_format,
        caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user
    ) VALUES (
        '01', '31000000-0000-0000-0000-000000000001', 'NM101',
        'D2310E2500NM1343', 'SYNTHETIC_KEEP_NM101', 'X(3)', 'A', 1, 3,
        'Synthetic NM1 qualifier', 'Y', 'Y', 1, 1, 'N', '02',
        NULL,
        NULL, 'Y', 'Y', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001'
    )
    INTO hcfa_electronic_fields VALUES (
        '02', '31000000-0000-0000-0000-000000000001', 'NM102',
        'D2310E2500NM1343', 'SYNTHETIC_KEEP_NM102', 'X(3)', 'A', 4, 6,
        'Synthetic NM1 entity type', 'Y', 'Y', 2, 1, 'N', '03',
        'SYNTHETIC_SOURCE_ENTITY',
        NULL, 'Y', 'Y', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '03', '31000000-0000-0000-0000-000000000001', 'NM103',
        'D2310E2500NM1343', NULL, 'X(40)', 'A', 7, 46,
        'Synthetic organization name', 'Y', 'Y', 3, 1, 'N', '09',
        'ABC', NULL, 'Y', 'Y', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '09', '31000000-0000-0000-0000-000000000001', 'NM109',
        'D2310E2500NM1343', 'SYNTHETIC_SOURCE_NPI', 'X(10)', 'A', 47, 56,
        'Synthetic facility NPI', 'Y', 'Y', 4, 1, 'N', NULL,
        'SYNTHETIC_KEEP_NM109', NULL, 'Y', 'Y', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '10', '31000000-0000-0000-0000-000000000001', 'NM110',
        'D2310E2500NM1343', 'G_SYNTHETIC_UNMANAGED', 'X(5)', 'A', 57, 61,
        'Synthetic unmanaged NM1 field', 'N', 'Y', 5, 1, 'N', NULL,
        'KEEP_ME', NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '01', '31000000-0000-0000-0000-000000000002', 'N301',
        'D2310E2650N3346', 'SYNTHETIC_SOURCE_ADDR1', 'X(40)', 'A', 1, 40,
        'Synthetic address line one', 'Y', 'Y', 1, 1, 'N', '02',
        'SYNTHETIC_KEEP_N301', NULL, 'Y', 'Y', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '02', '31000000-0000-0000-0000-000000000002', 'N302',
        'D2310E2650N3346', 'SYNTHETIC_SOURCE_ADDR2', 'X(40)', 'A', 41, 80,
        'Synthetic address line two', 'N', 'Y', 2, 1, 'N', NULL,
        'SYNTHETIC_KEEP_N302', NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '01', '31000000-0000-0000-0000-000000000003', 'N401',
        'D2310E2700N4347', 'SYNTHETIC_SOURCE_CITY', 'X(30)', 'A', 1, 30,
        'Synthetic city', 'Y', 'Y', 1, 1, 'N', '02',
        'SYNTHETIC_KEEP_N401', NULL, 'Y', 'Y', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '02', '31000000-0000-0000-0000-000000000003', 'N402',
        'D2310E2700N4347', 'SYNTHETIC_SOURCE_STATE', 'X(2)', 'A', 31, 32,
        'Synthetic state', 'Y', 'Y', 2, 1, 'N', '03',
        'SYNTHETIC_KEEP_N402', NULL, 'Y', 'Y', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '03', '31000000-0000-0000-0000-000000000003', 'N403',
        'D2310E2700N4347', 'SYNTHETIC_SOURCE_ZIP', 'X(10)', 'A', 33, 42,
        'Synthetic postal code', 'Y', 'Y', 3, 1, 'N', NULL,
        'SYNTHETIC_KEEP_N403', NULL, 'Y', 'Y', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
SELECT 1 FROM dual;

COMMIT;
