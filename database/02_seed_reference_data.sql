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
    'Synthetic Generic Provider', 'B2000A0030PRV080', 80, 'N',
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
        'Synthetic Service Facility NM1', 'D2310E2500NM1343', 80, 'N',
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
        'Synthetic Service Facility N3', 'D2310E2650N3346', 80, 'N',
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
        'Synthetic Service Facility N4', 'D2310E2700N4347', 80, 'N',
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

/*
 * Billing-form-level generic sources for the synthetic 837I_5010 UI demo.
 * They deliberately inherit the same OFF/NEVER behavior as the UB04 sources;
 * no payor-specific configuration is cloned or introduced.
 */
INSERT INTO hcfa_electronic_records (
    electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
    record_name, record_type_code, record_size, mandatory_ind,
    req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
    type_of_bill, detail_ind, max_number, invoice_ind,
    form_template_guid, carry_forward_ind, max_carry_forward,
    sto_proc_name, user_form_template_guid, notes,
    rec_ent_date, rec_ent_user, rec_mod_date, rec_mod_user,
    include_record_data_onclaim
)
SELECT
    CASE h.electronic_rec_guid
        WHEN '30000000-0000-0000-0000-000000000001'
            THEN '30000000-0000-0000-0000-00000000D081'
        WHEN '31000000-0000-0000-0000-000000000001'
            THEN '31000000-0000-0000-0000-00000000D771'
        WHEN '31000000-0000-0000-0000-000000000002'
            THEN '31000000-0000-0000-0000-00000000D772'
        WHEN '31000000-0000-0000-0000-000000000003'
            THEN '31000000-0000-0000-0000-00000000D773'
    END,
    h.loop_id,
    h.contiguity_ind,
    '837I_5010',
    h.record_name,
    h.record_type_code,
    h.record_size,
    h.mandatory_ind,
    h.req_for_claim_ind,
    h.payor_type_guid,
    h.payor_guid,
    h.plan_guid,
    h.type_of_bill,
    h.detail_ind,
    h.max_number,
    h.invoice_ind,
    h.form_template_guid,
    h.carry_forward_ind,
    h.max_carry_forward,
    h.sto_proc_name,
    h.user_form_template_guid,
    'Synthetic 837I_5010 UI demo source',
    h.rec_ent_date,
    h.rec_ent_user,
    h.rec_mod_date,
    h.rec_mod_user,
    h.include_record_data_onclaim
FROM hcfa_electronic_records h
WHERE h.electronic_rec_guid IN (
    '30000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000002',
    '31000000-0000-0000-0000-000000000003'
);

INSERT INTO hcfa_electronic_fields (
    field_number, electronic_rec_guid, field_name, record_type_code,
    sto_proc_name, pic, field_spec, position_from, position_thru,
    field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
    repeats, detail_ind, occurs_next, hard_coded_data, field_format,
    caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user,
    rec_mod_date, rec_mod_user, include_data_onclaim
)
SELECT
    f.field_number,
    CASE f.electronic_rec_guid
        WHEN '30000000-0000-0000-0000-000000000001'
            THEN '30000000-0000-0000-0000-00000000D081'
        WHEN '31000000-0000-0000-0000-000000000001'
            THEN '31000000-0000-0000-0000-00000000D771'
        WHEN '31000000-0000-0000-0000-000000000002'
            THEN '31000000-0000-0000-0000-00000000D772'
        WHEN '31000000-0000-0000-0000-000000000003'
            THEN '31000000-0000-0000-0000-00000000D773'
    END,
    f.field_name,
    f.record_type_code,
    f.sto_proc_name,
    f.pic,
    f.field_spec,
    f.position_from,
    f.position_thru,
    f.field_name_desc,
    f.mandatory_ind,
    f.must_fit_length_ind,
    f.order_num,
    f.repeats,
    f.detail_ind,
    f.occurs_next,
    f.hard_coded_data,
    f.field_format,
    f.caps_ind,
    f.required_subelement_ind,
    f.rec_ent_date,
    f.rec_ent_user,
    f.rec_mod_date,
    f.rec_mod_user,
    f.include_data_onclaim
FROM hcfa_electronic_fields f
WHERE f.electronic_rec_guid IN (
    '30000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000001',
    '31000000-0000-0000-0000-000000000002',
    '31000000-0000-0000-0000-000000000003'
);

/*
 * Explicit synthetic Value Codes source. The fifth HEF is deliberately
 * unmanaged so desired-state construction must preserve the complete source.
 */
INSERT INTO hcfa_electronic_records (
    electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
    record_name, record_type_code, record_size, mandatory_ind,
    req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
    type_of_bill, detail_ind, max_number, invoice_ind,
    form_template_guid, carry_forward_ind, max_carry_forward,
    sto_proc_name, user_form_template_guid, notes,
    rec_ent_date, rec_ent_user, include_record_data_onclaim
) VALUES (
    '32000000-0000-0000-0000-000000000001', '2300', 'Y', '837I_5010',
    'Synthetic Value Codes', 'D23002310HI286', 120, 'N',
    'N', NULL, NULL, NULL, NULL, 'N', '2', 'N', NULL, 'N', 0,
    'G_D2300231HI280_COUNT', NULL, 'Synthetic Value Codes default source',
    DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', 'Y'
);

INSERT ALL
    INTO hcfa_electronic_fields VALUES (
        '012', '32000000-0000-0000-0000-000000000001',
        'HI012', 'D23002310HI286', 'GET_VAL_CODE',
        'X(2)', 'A', 12, 13, 'Synthetic Value Code slot 1', 'N', 'Y',
        1, 1, 'N', '015', NULL, NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '015', '32000000-0000-0000-0000-000000000001',
        'HI015', 'D23002310HI286', 'GET_VAL_CODE_AMT',
        'X(12)', 'A', 15, 26, 'Synthetic Value amount slot 1', 'N', 'Y',
        2, 1, 'N', '022', NULL, NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '022', '32000000-0000-0000-0000-000000000001',
        'HI022', 'D23002310HI286', 'GET_VAL_CODE',
        'X(2)', 'A', 22, 23, 'Synthetic Value Code slot 2', 'N', 'Y',
        3, 1, 'N', '025', NULL, NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '025', '32000000-0000-0000-0000-000000000001',
        'HI025', 'D23002310HI286', 'GET_VAL_CODE_AMT',
        'X(12)', 'A', 25, 36, 'Synthetic Value amount slot 2', 'N', 'Y',
        4, 1, 'N', '030', NULL, NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '030', '32000000-0000-0000-0000-000000000001',
        'SYN_UNMANAGED_HI', 'D23002310HI286', 'SYN_KEEP_UNMANAGED',
        'X(4)', 'A', 30, 33, 'Synthetic unmanaged Value Codes HEF', 'N', 'Y',
        5, 1, 'N', NULL, 'KEEP_UNMANAGED', NULL, 'Y', 'N',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001',
        NULL, NULL, 'Y'
    )
SELECT 1 FROM dual;

/*
 * Explicit synthetic Remarks source. NTE03 is intentionally unmanaged and
 * contains both value mechanisms so managed-only overlay behavior is tested.
 */
INSERT INTO hcfa_electronic_records (
    electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
    record_name, record_type_code, record_size, mandatory_ind,
    req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
    type_of_bill, detail_ind, max_number, invoice_ind,
    form_template_guid, carry_forward_ind, max_carry_forward,
    sto_proc_name, user_form_template_guid, notes,
    rec_ent_date, rec_ent_user, include_record_data_onclaim
) VALUES (
    '33000000-0000-0000-0000-000000000001', '2300', 'Y', '837I_5010',
    'Synthetic Remarks', 'D23001900NTE182', 120, 'N',
    'N', NULL, NULL, NULL, NULL, 'N', '2', 'N', NULL, 'N', 0,
    'G_D2300190NTE208_COUNT', NULL, 'Synthetic Remarks default source',
    DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', 'Y'
);

INSERT ALL
    INTO hcfa_electronic_fields VALUES (
        '00', '33000000-0000-0000-0000-000000000001',
        'NTE00', 'D23001900NTE182', NULL,
        'X(3)', 'A', 1, 3, 'Synthetic segment identifier', 'N', 'Y',
        1, 1, 'N', '01', 'NTE', NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '01', '33000000-0000-0000-0000-000000000001',
        'NTE01', 'D23001900NTE182', NULL,
        'X(3)', 'A', 4, 6, 'Synthetic note reference code', 'N', 'Y',
        2, 1, 'N', '02', 'ADD', NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '02', '33000000-0000-0000-0000-000000000001',
        'NTE02', 'D23001900NTE182', 'GET_REMARKS',
        'X(100)', 'A', 7, 106, 'Synthetic standard remarks text', 'N', 'Y',
        3, 1, 'N', '03', NULL, NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
    INTO hcfa_electronic_fields VALUES (
        '03', '33000000-0000-0000-0000-000000000001',
        'NTE03', 'D23001900NTE182', 'SYN_KEEP_UNMANAGED_NTE',
        'X(8)', 'A', 107, 114, 'Synthetic unmanaged Remarks HEF', 'N', 'Y',
        4, 1, 'N', NULL, 'KEEP_NTE03', NULL, 'Y', 'N', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL, 'Y'
    )
SELECT 1 FROM dual;

/*
 * Functional form/user-template sources for the synthetic hierarchy matrix.
 * These profiles reuse only supported application configurations.  Template
 * rows are generic sources: PAYOR_GUID, PLAN_GUID, and TYPE_OF_BILL stay null.
 */
DECLARE
    TYPE t_profile IS RECORD (
        template_code      VARCHAR2(4),
        form_template_guid VARCHAR2(36),
        user_template_guid VARCHAR2(36),
        provider_option    VARCHAR2(40),
        service_option     VARCHAR2(60),
        value_recipe       VARCHAR2(40),
        remarks_mode       VARCHAR2(10),
        remarks_text       VARCHAR2(100)
    );
    TYPE t_profiles IS TABLE OF t_profile INDEX BY PLS_INTEGER;

    l_profiles  t_profiles;
    l_new_guid  VARCHAR2(36);
    l_her_proc  VARCHAR2(30);
    l_field_sto VARCHAR2(30);
    l_field_hard VARCHAR2(128);

    FUNCTION template_source_guid(
        p_template_code IN VARCHAR2,
        p_source_guid   IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN SUBSTR(p_source_guid, 1, 24) || p_template_code ||
            SUBSTR(p_source_guid, -8);
    END;

    FUNCTION service_her_proc(
        p_option      IN VARCHAR2,
        p_record_type IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        IF p_option = 'SERVICE_FACILITY_ALWAYS_ADDRESS_YES' THEN
            RETURN 'RETURN_1';
        ELSIF p_option = 'SERVICE_FACILITY_ALWAYS_ADDRESS_NO' THEN
            IF p_record_type = 'D2310E2500NM1343' THEN
                RETURN 'RETURN_1';
            END IF;
            RETURN 'RETURN_0';
        ELSIF p_option = 'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES' THEN
            RETURN 'G_D2310E2500NM1343_COUNT';
        ELSIF p_option = 'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO' THEN
            IF p_record_type = 'D2310E2500NM1343' THEN
                RETURN 'G_D2310E2500NM1343_COUNT';
            END IF;
            RETURN 'RETURN_0';
        END IF;
        RETURN 'RETURN_0';
    END;

    PROCEDURE apply_service_field(
        p_option      IN VARCHAR2,
        p_record_type IN VARCHAR2,
        p_field       IN VARCHAR2,
        p_sto         IN OUT VARCHAR2,
        p_hard        IN OUT VARCHAR2
    ) IS
    BEGIN
        IF p_option <> 'SERVICE_FACILITY_NEVER'
           AND p_record_type = 'D2310E2500NM1343' THEN
            CASE p_field
                WHEN '01' THEN p_sto := NULL; p_hard := '77';
                WHEN '02' THEN p_sto := NULL; p_hard := '2';
                WHEN '03' THEN p_sto := 'G_ORGANIZATION_NAME'; p_hard := NULL;
                WHEN '09' THEN p_sto := 'G_FACILITY_NPI'; p_hard := NULL;
                ELSE NULL;
            END CASE;
        END IF;

        IF p_option IN (
            'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
            'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES'
        ) THEN
            IF p_record_type = 'D2310E2650N3346' THEN
                CASE p_field
                    WHEN '01' THEN p_sto := 'G_CARE_LOCATION_ADDR1'; p_hard := NULL;
                    WHEN '02' THEN p_sto := 'G_CARE_LOCATION_ADDR2'; p_hard := NULL;
                    ELSE NULL;
                END CASE;
            ELSIF p_record_type = 'D2310E2700N4347' THEN
                CASE p_field
                    WHEN '01' THEN p_sto := 'G_CARE_LOCATION_CITY'; p_hard := NULL;
                    WHEN '02' THEN p_sto := 'G_CARE_LOCATION_STATE'; p_hard := NULL;
                    WHEN '03' THEN p_sto := 'G_CARE_LOCATION_ZIP'; p_hard := NULL;
                    ELSE NULL;
                END CASE;
            END IF;
        END IF;
    END;

    PROCEDURE apply_value_field(
        p_recipe IN VARCHAR2,
        p_field  IN VARCHAR2,
        p_sto    IN OUT VARCHAR2,
        p_hard   IN OUT VARCHAR2
    ) IS
    BEGIN
        CASE p_recipe
            WHEN 'HOME_HEALTH_CBSA' THEN
                CASE p_field
                    WHEN '012' THEN p_sto := NULL; p_hard := '61';
                    WHEN '015' THEN p_sto := 'GET_PAT_CBSA_CODE'; p_hard := NULL;
                    WHEN '022' THEN p_sto := 'GET_VAL_CODE'; p_hard := NULL;
                    WHEN '025' THEN p_sto := 'GET_VAL_CODE_AMT'; p_hard := NULL;
                    ELSE NULL;
                END CASE;
            WHEN 'HOME_HEALTH_CBSA_FIPS' THEN
                CASE p_field
                    WHEN '012' THEN p_sto := NULL; p_hard := '61';
                    WHEN '015' THEN p_sto := 'GET_PAT_CBSA_CODE'; p_hard := NULL;
                    WHEN '022' THEN p_sto := 'GET_FIPS_CODE'; p_hard := NULL;
                    WHEN '025' THEN p_sto := 'GET_FIPS_CODE_VALUE'; p_hard := NULL;
                    ELSE NULL;
                END CASE;
            WHEN 'HOSPICE_61_G8_VC80' THEN
                CASE p_field
                    WHEN '012' THEN p_sto := 'GET_CARE_LOC_CODE'; p_hard := NULL;
                    WHEN '015' THEN p_sto := 'GET_CARE_LOC_VAL_CODE'; p_hard := NULL;
                    WHEN '022' THEN p_sto := NULL; p_hard := '80';
                    WHEN '025' THEN p_sto := 'GET_DISTINCT_COVERED_DAYS'; p_hard := NULL;
                    ELSE NULL;
                END CASE;
            WHEN 'HOSPICE_PATIENT_VC80' THEN
                CASE p_field
                    WHEN '012' THEN p_sto := 'GET_VAL_CODE'; p_hard := NULL;
                    WHEN '015' THEN p_sto := 'GET_VAL_CODE_AMT'; p_hard := NULL;
                    WHEN '022' THEN p_sto := NULL; p_hard := '80';
                    WHEN '025' THEN p_sto := 'GET_DISTINCT_COVERED_DAYS'; p_hard := NULL;
                    ELSE NULL;
                END CASE;
            WHEN 'HOSPICE_VC80' THEN
                CASE p_field
                    WHEN '012' THEN p_sto := NULL; p_hard := '80';
                    WHEN '015' THEN p_sto := 'GET_DISTINCT_COVERED_DAYS'; p_hard := NULL;
                    WHEN '022' THEN p_sto := 'GET_VAL_CODE'; p_hard := NULL;
                    WHEN '025' THEN p_sto := 'GET_VAL_CODE_AMT'; p_hard := NULL;
                    ELSE NULL;
                END CASE;
            ELSE NULL;
        END CASE;
    END;
BEGIN
    l_profiles(1).template_code := 'A100';
    l_profiles(1).form_template_guid :=
        '40000000-0000-0000-0000-00000000B100';
    l_profiles(1).provider_option := 'PROVIDER_TAXONOMY_ON';
    l_profiles(1).service_option := 'SERVICE_FACILITY_ALWAYS_ADDRESS_YES';
    l_profiles(1).value_recipe := 'HOME_HEALTH_CBSA';
    l_profiles(1).remarks_mode := 'CUSTOM';
    l_profiles(1).remarks_text := 'Form A100 template remark';

    l_profiles(2).template_code := 'A200';
    l_profiles(2).form_template_guid :=
        '40000000-0000-0000-0000-00000000B200';
    l_profiles(2).provider_option := 'PROVIDER_TAXONOMY_OFF';
    l_profiles(2).service_option :=
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO';
    l_profiles(2).value_recipe := 'HOSPICE_61_G8_VC80';
    l_profiles(2).remarks_mode := 'CUSTOM';
    l_profiles(2).remarks_text := 'Form A200 template remark';

    l_profiles(3).template_code := 'B100';
    l_profiles(3).user_template_guid :=
        '50000000-0000-0000-0000-00000000B100';
    l_profiles(3).provider_option := 'PROVIDER_TAXONOMY_OFF';
    l_profiles(3).service_option := 'SERVICE_FACILITY_ALWAYS_ADDRESS_NO';
    l_profiles(3).value_recipe := 'HOME_HEALTH_CBSA_FIPS';
    l_profiles(3).remarks_mode := 'CUSTOM';
    l_profiles(3).remarks_text := 'User B100 template remark';

    l_profiles(4).template_code := 'B200';
    l_profiles(4).user_template_guid :=
        '50000000-0000-0000-0000-00000000B200';
    l_profiles(4).provider_option := 'PROVIDER_TAXONOMY_ON';
    l_profiles(4).service_option :=
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES';
    l_profiles(4).value_recipe := 'HOSPICE_PATIENT_VC80';
    l_profiles(4).remarks_mode := 'CUSTOM';
    l_profiles(4).remarks_text := 'User B200 template remark';

    l_profiles(5).template_code := 'B300';
    l_profiles(5).user_template_guid :=
        '50000000-0000-0000-0000-00000000B300';
    l_profiles(5).provider_option := 'PROVIDER_TAXONOMY_ON';
    l_profiles(5).service_option := 'SERVICE_FACILITY_NEVER';
    l_profiles(5).value_recipe := 'HOSPICE_VC80';
    l_profiles(5).remarks_mode := 'DEFAULT';

    FOR profile_index IN 1 .. l_profiles.COUNT LOOP
        FOR source_record IN (
            SELECT h.*
            FROM hcfa_electronic_records h
            WHERE h.electronic_rec_guid IN (
                '30000000-0000-0000-0000-00000000D081',
                '31000000-0000-0000-0000-00000000D771',
                '31000000-0000-0000-0000-00000000D772',
                '31000000-0000-0000-0000-00000000D773',
                '32000000-0000-0000-0000-000000000001',
                '33000000-0000-0000-0000-000000000001'
            )
            ORDER BY h.electronic_rec_guid
        ) LOOP
            l_new_guid := template_source_guid(
                l_profiles(profile_index).template_code,
                source_record.electronic_rec_guid
            );
            l_her_proc := source_record.sto_proc_name;

            IF source_record.record_type_code = 'B2000A0030PRV080' THEN
                IF l_profiles(profile_index).provider_option =
                    'PROVIDER_TAXONOMY_ON' THEN
                    l_her_proc := 'RETURN_1';
                ELSE
                    l_her_proc := 'RETURN_0';
                END IF;
            ELSIF source_record.record_type_code IN (
                'D2310E2500NM1343',
                'D2310E2650N3346',
                'D2310E2700N4347'
            ) THEN
                l_her_proc := service_her_proc(
                    l_profiles(profile_index).service_option,
                    source_record.record_type_code
                );
            ELSIF source_record.record_type_code = 'D23002310HI286' THEN
                l_her_proc := 'RETURN_1';
            ELSIF source_record.record_type_code = 'D23001900NTE182'
                  AND l_profiles(profile_index).remarks_mode = 'CUSTOM' THEN
                l_her_proc := 'RETURN_1';
            END IF;

            INSERT INTO hcfa_electronic_records (
                electronic_rec_guid, loop_id, contiguity_ind,
                billing_form_code, record_name, record_type_code,
                record_size, mandatory_ind, req_for_claim_ind,
                payor_type_guid, payor_guid, plan_guid, type_of_bill,
                detail_ind, max_number, invoice_ind, form_template_guid,
                carry_forward_ind, max_carry_forward, sto_proc_name,
                user_form_template_guid, notes, rec_ent_date, rec_ent_user,
                rec_mod_date, rec_mod_user, include_record_data_onclaim
            ) VALUES (
                l_new_guid, source_record.loop_id,
                source_record.contiguity_ind, source_record.billing_form_code,
                SUBSTR('Synthetic ' || l_profiles(profile_index).template_code ||
                    ' ' || source_record.record_name, 1, 50),
                source_record.record_type_code, source_record.record_size,
                CASE WHEN l_her_proc = 'RETURN_1'
                    THEN source_record.mandatory_ind ELSE 'N' END,
                source_record.req_for_claim_ind, source_record.payor_type_guid,
                NULL, NULL, NULL, source_record.detail_ind,
                source_record.max_number, source_record.invoice_ind,
                l_profiles(profile_index).form_template_guid,
                source_record.carry_forward_ind,
                source_record.max_carry_forward, l_her_proc,
                l_profiles(profile_index).user_template_guid,
                'Synthetic functional template source ' ||
                    l_profiles(profile_index).template_code,
                source_record.rec_ent_date, source_record.rec_ent_user,
                source_record.rec_mod_date, source_record.rec_mod_user,
                source_record.include_record_data_onclaim
            );

            FOR source_field IN (
                SELECT f.*
                FROM hcfa_electronic_fields f
                WHERE f.electronic_rec_guid =
                    source_record.electronic_rec_guid
                ORDER BY f.order_num, f.field_number
            ) LOOP
                l_field_sto := source_field.sto_proc_name;
                l_field_hard := source_field.hard_coded_data;

                IF source_record.record_type_code IN (
                    'D2310E2500NM1343',
                    'D2310E2650N3346',
                    'D2310E2700N4347'
                ) THEN
                    apply_service_field(
                        l_profiles(profile_index).service_option,
                        source_record.record_type_code,
                        source_field.field_number,
                        l_field_sto,
                        l_field_hard
                    );
                ELSIF source_record.record_type_code = 'D23002310HI286' THEN
                    apply_value_field(
                        l_profiles(profile_index).value_recipe,
                        source_field.field_number,
                        l_field_sto,
                        l_field_hard
                    );
                ELSIF source_record.record_type_code = 'D23001900NTE182'
                      AND l_profiles(profile_index).remarks_mode = 'CUSTOM' THEN
                    CASE source_field.field_number
                        WHEN '00' THEN l_field_sto := NULL; l_field_hard := 'NTE';
                        WHEN '01' THEN l_field_sto := NULL; l_field_hard := 'ADD';
                        WHEN '02' THEN
                            l_field_sto := NULL;
                            l_field_hard :=
                                l_profiles(profile_index).remarks_text;
                        ELSE NULL;
                    END CASE;
                END IF;

                INSERT INTO hcfa_electronic_fields (
                    field_number, electronic_rec_guid, field_name,
                    record_type_code, sto_proc_name, pic, field_spec,
                    position_from, position_thru, field_name_desc,
                    mandatory_ind, must_fit_length_ind, order_num, repeats,
                    detail_ind, occurs_next, hard_coded_data, field_format,
                    caps_ind, required_subelement_ind, rec_ent_date,
                    rec_ent_user, rec_mod_date, rec_mod_user,
                    include_data_onclaim
                ) VALUES (
                    source_field.field_number, l_new_guid,
                    source_field.field_name, source_field.record_type_code,
                    l_field_sto, source_field.pic, source_field.field_spec,
                    source_field.position_from, source_field.position_thru,
                    source_field.field_name_desc, source_field.mandatory_ind,
                    source_field.must_fit_length_ind, source_field.order_num,
                    source_field.repeats, source_field.detail_ind,
                    source_field.occurs_next, l_field_hard,
                    source_field.field_format, source_field.caps_ind,
                    source_field.required_subelement_ind,
                    source_field.rec_ent_date, source_field.rec_ent_user,
                    source_field.rec_mod_date, source_field.rec_mod_user,
                    source_field.include_data_onclaim
                );
            END LOOP;
        END LOOP;
    END LOOP;
END;
/

COMMIT;
