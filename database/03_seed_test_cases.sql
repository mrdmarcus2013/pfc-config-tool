/* Synthetic PAYOR_A through PAYOR_H and UI Demo scenarios. */
SET DEFINE OFF

INSERT ALL
    INTO payors VALUES (
        '10000000-0000-0000-0000-0000000000A1',
        '11000000-0000-0000-0000-000000000001',
        'Synthetic PAYOR_A', 'SYN-A', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO payors VALUES (
        '10000000-0000-0000-0000-0000000000A2',
        '11000000-0000-0000-0000-000000000001',
        'Synthetic PAYOR_B', 'SYN-B', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO payors VALUES (
        '10000000-0000-0000-0000-0000000000A3',
        '11000000-0000-0000-0000-000000000001',
        'Synthetic PAYOR_C', 'SYN-C', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO payors VALUES (
        '10000000-0000-0000-0000-0000000000A4',
        '11000000-0000-0000-0000-000000000001',
        'Synthetic PAYOR_D', 'SYN-D', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO payors VALUES (
        '10000000-0000-0000-0000-0000000000A5',
        '11000000-0000-0000-0000-000000000001',
        'Synthetic PAYOR_E', 'SYN-E', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO payors VALUES (
        '10000000-0000-0000-0000-0000000000A6',
        '11000000-0000-0000-0000-000000000001',
        'Synthetic PAYOR_F', 'SYN-F', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO payors VALUES (
        '10000000-0000-0000-0000-0000000000A7',
        '11000000-0000-0000-0000-000000000001',
        'Synthetic PAYOR_G', 'SYN-G', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO payors VALUES (
        '10000000-0000-0000-0000-0000000000A8',
        '11000000-0000-0000-0000-000000000002',
        'Synthetic PAYOR_H', 'SYN-H', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO payors VALUES (
        '10000000-0000-0000-0000-00000000D001',
        '11000000-0000-0000-0000-000000000001',
        'Synthetic UI Demo Payor', 'SYN-UI-DEMO', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO payors VALUES (
        '10000000-0000-0000-0000-00000000D002',
        '11000000-0000-0000-0000-000000000001',
        'Synthetic Defined LOB Payor', 'SYN-DEFINED-LOB', DATE '2026-01-01',
        '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
SELECT 1 FROM dual;

/* Tool-owned payor context. UI Demo intentionally remains undefined. */
INSERT ALL
    INTO pfc_config_payor_context VALUES (
        '10000000-0000-0000-0000-0000000000A1', 'HOME_HEALTH',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc_config_payor_context VALUES (
        '10000000-0000-0000-0000-0000000000A8', 'HOSPICE',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc_config_payor_context VALUES (
        '10000000-0000-0000-0000-00000000D002', 'HOME_HEALTH',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
SELECT 1 FROM dual;

/* All PFCs are synthetic, electronic, and active through 2099. */
INSERT ALL
    INTO pfc VALUES (
        '20000000-0000-0000-0000-0000000000A1',
        '10000000-0000-0000-0000-0000000000A1',
        'I', 'UB04', 'E', NULL, NULL, NULL, NULL,
        DATE '2025-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-0000000000A2',
        '10000000-0000-0000-0000-0000000000A2',
        'I', 'UB04', 'E', NULL, NULL, NULL, NULL,
        DATE '2025-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-0000000000A3',
        '10000000-0000-0000-0000-0000000000A3',
        'I', 'UB04', 'E',
        '40000000-0000-0000-0000-0000000000F1', NULL, NULL,
        '50000000-0000-0000-0000-0000000000F1',
        DATE '2025-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-0000000000A4',
        '10000000-0000-0000-0000-0000000000A4',
        'I', 'UB04', 'E', NULL, NULL, NULL, NULL,
        DATE '2025-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-0000000000A5',
        '10000000-0000-0000-0000-0000000000A5',
        'I', 'UB04', 'E',
        '40000000-0000-0000-0000-0000000000E1', NULL, NULL, NULL,
        DATE '2025-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-0000000000A6',
        '10000000-0000-0000-0000-0000000000A6',
        'I', 'UB04', 'E',
        '40000000-0000-0000-0000-0000000000F1', NULL, NULL,
        '50000000-0000-0000-0000-0000000000F1',
        DATE '2025-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-0000000000A7',
        '10000000-0000-0000-0000-0000000000A7',
        'I', 'UB04', 'E', NULL, NULL, NULL, NULL,
        DATE '2024-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-0000000000B7',
        '10000000-0000-0000-0000-0000000000A7',
        'I', 'UB04', 'E', NULL, NULL, NULL, NULL,
        DATE '2025-01-01', NULL, DATE '2026-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-0000000000A8',
        '10000000-0000-0000-0000-0000000000A8',
        'I', 'UB04', 'E', NULL, NULL, NULL, NULL,
        DATE '2025-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-00000000D001',
        '10000000-0000-0000-0000-00000000D001',
        'I', '837I_5010', 'E', NULL, NULL, NULL, NULL,
        DATE '2025-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
    INTO pfc VALUES (
        '20000000-0000-0000-0000-00000000D002',
        '10000000-0000-0000-0000-00000000D002',
        'I', '837I_5010', 'E', NULL, NULL, NULL, NULL,
        DATE '2025-01-01', NULL, DATE '2025-01-01', DATE '2099-12-31',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', NULL, NULL
    )
SELECT 1 FROM dual;

/*
 * PAYOR_B: one canonical payor-specific HER.
 * PAYOR_C: two stale HERs with different old form-template GUIDs.
 * PAYOR_D: one payor-specific HER whose PRV03 will be made incorrect below.
 * PAYOR_H: generic exact-payor-type source competing with the NULL-type source.
 */
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
        '30000000-0000-0000-0000-0000000000B1', 'PRV', 'Y', 'UB04',
        'Synthetic Generic Provider', 'B2000A0030PRV080', 80, 'N', 'Y',
        NULL,
        '10000000-0000-0000-0000-0000000000A2', NULL, NULL,
        'N', '1', 'N', NULL, NULL, 0, 'RETURN_1', NULL,
        'Synthetic billing-form-level PRV source',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001', 'Y'
    )
    INTO hcfa_electronic_records (
        electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
        record_name, record_type_code, record_size, mandatory_ind,
        req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
        type_of_bill, detail_ind, max_number, invoice_ind,
        form_template_guid, carry_forward_ind, max_carry_forward,
        sto_proc_name, user_form_template_guid, notes,
        rec_ent_date, rec_ent_user
    ) VALUES (
        '30000000-0000-0000-0000-0000000000C1', 'PRV', 'Y', 'UB04',
        'Synthetic PAYOR_C Stale Provider One', 'B2000A0030PRV080', 80, 'Y', 'Y',
        '11000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-0000000000A3', NULL, NULL,
        'N', '1', 'N', '40000000-0000-0000-0000-0000000000C1',
        'N', 0, 'RETURN_0', NULL, 'Synthetic stale PRV one',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
    )
    INTO hcfa_electronic_records (
        electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
        record_name, record_type_code, record_size, mandatory_ind,
        req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
        type_of_bill, detail_ind, max_number, invoice_ind,
        form_template_guid, carry_forward_ind, max_carry_forward,
        sto_proc_name, user_form_template_guid, notes,
        rec_ent_date, rec_ent_user
    ) VALUES (
        '30000000-0000-0000-0000-0000000000C2', 'PRV', 'Y', 'UB04',
        'Synthetic PAYOR_C Stale Provider Two', 'B2000A0030PRV080', 80, 'Y', 'Y',
        '11000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-0000000000A3', NULL, NULL,
        'N', '1', 'N', '40000000-0000-0000-0000-0000000000C2',
        'N', 0, 'RETURN_0', NULL, 'Synthetic stale PRV two',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
    )
    INTO hcfa_electronic_records (
        electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
        record_name, record_type_code, record_size, mandatory_ind,
        req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
        type_of_bill, detail_ind, max_number, invoice_ind,
        form_template_guid, carry_forward_ind, max_carry_forward,
        sto_proc_name, user_form_template_guid, notes,
        rec_ent_date, rec_ent_user
    ) VALUES (
        '30000000-0000-0000-0000-0000000000D1', 'PRV', 'Y', 'UB04',
        'Synthetic PAYOR_D Provider', 'B2000A0030PRV080', 80, 'Y', 'Y',
        '11000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-0000000000A4', NULL, NULL,
        'N', '1', 'N', NULL, 'N', 0, 'RETURN_1', NULL,
        'Synthetic PRV with incorrect PRV03 procedure',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
    )
    INTO hcfa_electronic_records (
        electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
        record_name, record_type_code, record_size, mandatory_ind,
        req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
        type_of_bill, detail_ind, max_number, invoice_ind,
        form_template_guid, carry_forward_ind, max_carry_forward,
        sto_proc_name, user_form_template_guid, notes,
        rec_ent_date, rec_ent_user
    ) VALUES (
        '30000000-0000-0000-0000-0000000000A8', 'PRV', 'Y', 'UB04',
        'Synthetic Exact Type Provider', 'B2000A0030PRV080', 80, 'Y', 'Y',
        '11000000-0000-0000-0000-000000000002', NULL, NULL, NULL,
        'N', '1', 'N', NULL, 'N', 0, 'RETURN_1', NULL,
        'Synthetic exact PAYOR_H type PRV source',
        DATE '2026-01-01', '90000000-0000-0000-0000-000000000001'
    )
SELECT 1 FROM dual;

/* Clone the complete generic HEF set onto every scenario HER. */
INSERT INTO hcfa_electronic_fields (
    field_number, electronic_rec_guid, field_name, record_type_code,
    sto_proc_name, pic, field_spec, position_from, position_thru,
    field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
    repeats, detail_ind, occurs_next, hard_coded_data, field_format,
    caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user,
    rec_mod_date, rec_mod_user, include_data_onclaim
)
SELECT
    base_field.field_number,
    scenario_her.electronic_rec_guid,
    base_field.field_name,
    base_field.record_type_code,
    base_field.sto_proc_name,
    base_field.pic,
    base_field.field_spec,
    base_field.position_from,
    base_field.position_thru,
    base_field.field_name_desc,
    base_field.mandatory_ind,
    base_field.must_fit_length_ind,
    base_field.order_num,
    base_field.repeats,
    base_field.detail_ind,
    base_field.occurs_next,
    base_field.hard_coded_data,
    base_field.field_format,
    base_field.caps_ind,
    base_field.required_subelement_ind,
    base_field.rec_ent_date,
    base_field.rec_ent_user,
    NULL,
    NULL,
    base_field.include_data_onclaim
FROM hcfa_electronic_fields base_field
CROSS JOIN (
    SELECT '30000000-0000-0000-0000-0000000000B1' AS electronic_rec_guid FROM dual
    UNION ALL
    SELECT '30000000-0000-0000-0000-0000000000C1' FROM dual
    UNION ALL
    SELECT '30000000-0000-0000-0000-0000000000C2' FROM dual
    UNION ALL
    SELECT '30000000-0000-0000-0000-0000000000D1' FROM dual
    UNION ALL
    SELECT '30000000-0000-0000-0000-0000000000A8' FROM dual
) scenario_her
WHERE base_field.electronic_rec_guid =
    '30000000-0000-0000-0000-000000000001';

UPDATE hcfa_electronic_fields
SET
    sto_proc_name = NULL,
    hard_coded_data = 'SYNTHETIC_HARD_CODED_TAXONOMY'
WHERE electronic_rec_guid = '30000000-0000-0000-0000-0000000000D1'
  AND field_name = 'PRV03';

COMMIT;
