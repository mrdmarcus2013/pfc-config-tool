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

COMMIT;
