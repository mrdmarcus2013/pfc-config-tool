/*
 * Value Codes production discovery and recognition.
 *
 * Edit only PAYOR_GUID, PLAN_GUID, and LINE_OF_BUSINESS in manual_inputs.
 * Leave PLAN_GUID NULL for payor-level resolution. To test a plan, replace
 * the CAST(NULL AS VARCHAR2(36)) expression with the plan GUID literal.
 * LINE_OF_BUSINESS is supplied manually because it is tool-only metadata;
 * valid values are HOME_HEALTH and HOSPICE. This script does not expect
 * tool-owned tables in MatrixCare production. Run the statement normally in
 * Toad. The script reads production data only. Save/export the full result
 * grid because it contains the summary, managed values, and complete
 * source/current HEF diagnostics.
 */
SET PAGESIZE 50000
SET LINESIZE 32767

WITH
manual_inputs AS (
    SELECT
        'PUT_PAYOR_GUID_HERE' AS payor_guid,
        CAST(NULL AS VARCHAR2(36)) AS plan_guid,
        'HOME_HEALTH' AS line_of_business
    FROM dual
),
params AS (
    SELECT
        TRIM(payor_guid) AS payor_guid,
        TRIM(plan_guid) AS plan_guid,
        UPPER(TRIM(line_of_business)) AS line_of_business,
        'D23002310HI286' AS record_type_code
    FROM manual_inputs
),
managed_fields AS (
    SELECT '012' AS field_number, 1 AS field_order FROM dual
    UNION ALL SELECT '015', 2 FROM dual
    UNION ALL SELECT '022', 3 FROM dual
    UNION ALL SELECT '025', 4 FROM dual
),
lob_resolution AS (
    SELECT
        p.payor_guid,
        CASE
            WHEN p.line_of_business IN ('HOME_HEALTH', 'HOSPICE')
                THEN 'RESOLVED'
            ELSE 'BLOCKED_LOB_INVALID'
        END AS lob_status,
        p.line_of_business
    FROM params p
),
eligible_pfc AS (
    SELECT
        p.pfc_guid,
        p.payor_guid,
        p.plan_guid,
        payor.payor_type_guid,
        p.billing_form_code,
        p.form_template_guid,
        p.user_form_template_guid,
        p.cpd_start_date,
        p.cpd_end_date,
        DENSE_RANK() OVER (
            ORDER BY p.cpd_start_date DESC NULLS LAST
        ) AS start_date_rank
    FROM pfc p
    JOIN payors payor
      ON payor.payor_guid = p.payor_guid
    CROSS JOIN params x
    WHERE p.payor_guid = x.payor_guid
      AND p.cpd_end_date > SYSDATE
      AND p.default_media_type = 'E'
      AND p.type_of_bill IS NULL
      AND (
            (x.plan_guid IS NULL AND p.plan_guid IS NULL)
            OR
            (x.plan_guid IS NOT NULL AND (
                p.plan_guid = x.plan_guid OR p.plan_guid IS NULL
            ))
          )
),
winning_pfc AS (
    SELECT p.*
    FROM eligible_pfc p
    WHERE p.start_date_rank = 1
),
pfc_resolution AS (
    SELECT
        x.payor_guid,
        x.plan_guid AS requested_plan_guid,
        x.record_type_code,
        CASE
            WHEN COUNT(p.pfc_guid) = 0 THEN 'MISSING'
            WHEN COUNT(p.pfc_guid) > 1 THEN 'AMBIGUOUS_NEWEST_DATE'
            ELSE 'RESOLVED'
        END AS pfc_status,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.pfc_guid) END AS pfc_guid,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.plan_guid) END AS pfc_plan_guid,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.payor_type_guid) END
            AS payor_type_guid,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.billing_form_code) END
            AS billing_form_code,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.form_template_guid) END
            AS form_template_guid,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.user_form_template_guid) END
            AS user_form_template_guid
    FROM params x
    LEFT JOIN winning_pfc p ON 1 = 1
    GROUP BY x.payor_guid, x.plan_guid, x.record_type_code
),
source_candidates AS (
    SELECT
        h.electronic_rec_guid,
        h.payor_type_guid,
        h.form_template_guid,
        h.user_form_template_guid,
        h.sto_proc_name,
        CASE
            WHEN h.user_form_template_guid IS NOT NULL THEN 1
            WHEN h.form_template_guid IS NOT NULL THEN 2
            ELSE 3
        END AS template_rank,
        CASE
            WHEN h.payor_type_guid = p.payor_type_guid
                 AND h.payor_type_guid IS NOT NULL THEN 1
            ELSE 2
        END AS payor_type_rank,
        DENSE_RANK() OVER (
            ORDER BY
                CASE
                    WHEN h.user_form_template_guid IS NOT NULL THEN 1
                    WHEN h.form_template_guid IS NOT NULL THEN 2
                    ELSE 3
                END,
                CASE
                    WHEN h.payor_type_guid = p.payor_type_guid
                         AND h.payor_type_guid IS NOT NULL THEN 1
                    ELSE 2
                END
        ) AS source_rank
    FROM pfc_resolution p
    JOIN hcfa_electronic_records h
      ON h.billing_form_code = p.billing_form_code
     AND h.record_type_code = p.record_type_code
    WHERE p.pfc_status = 'RESOLVED'
      AND h.payor_guid IS NULL
      AND h.plan_guid IS NULL
      AND h.type_of_bill IS NULL
      AND (h.payor_type_guid = p.payor_type_guid OR h.payor_type_guid IS NULL)
      AND (h.form_template_guid = p.form_template_guid
           OR h.form_template_guid IS NULL)
      AND (h.user_form_template_guid = p.user_form_template_guid
           OR h.user_form_template_guid IS NULL)
),
best_source_candidates AS (
    SELECT s.* FROM source_candidates s WHERE s.source_rank = 1
),
source_resolution AS (
    SELECT
        p.*,
        CASE
            WHEN p.pfc_status = 'MISSING' THEN 'BLOCKED_PFC_MISSING'
            WHEN p.pfc_status = 'AMBIGUOUS_NEWEST_DATE'
                THEN 'BLOCKED_PFC_AMBIGUOUS'
            WHEN COUNT(s.electronic_rec_guid) = 0 THEN 'MISSING'
            WHEN COUNT(s.electronic_rec_guid) > 1 THEN 'AMBIGUOUS'
            ELSE 'RESOLVED'
        END AS source_status,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.electronic_rec_guid) END AS source_electronic_rec_guid,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.form_template_guid) END AS source_form_template_guid,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.user_form_template_guid) END AS source_user_form_template_guid,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.sto_proc_name) END AS source_her_sto_proc_name
    FROM pfc_resolution p
    LEFT JOIN best_source_candidates s ON 1 = 1
    GROUP BY
        p.payor_guid, p.requested_plan_guid, p.record_type_code,
        p.pfc_status, p.pfc_guid, p.pfc_plan_guid, p.payor_type_guid,
        p.billing_form_code, p.form_template_guid, p.user_form_template_guid
),
source_hefs AS (
    SELECT f.*
    FROM source_resolution s
    JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = s.source_electronic_rec_guid
    WHERE s.source_status = 'RESOLVED'
),
existing_payor_hers AS (
    SELECT h.*
    FROM source_resolution s
    JOIN hcfa_electronic_records h
      ON h.payor_guid = s.payor_guid
     AND h.billing_form_code = s.billing_form_code
     AND h.record_type_code = s.record_type_code
    WHERE s.pfc_status = 'RESOLVED'
),
existing_counts AS (
    SELECT
        COUNT(DISTINCT h.electronic_rec_guid) AS existing_payor_her_count,
        COUNT(f.electronic_rec_guid) AS existing_payor_hef_count
    FROM source_resolution s
    LEFT JOIN existing_payor_hers h ON 1 = 1
    LEFT JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
),
current_guid AS (
    SELECT
        CASE
            WHEN c.existing_payor_her_count = 0
                THEN s.source_electronic_rec_guid
            WHEN c.existing_payor_her_count = 1
                THEN MAX(h.electronic_rec_guid)
        END AS electronic_rec_guid
    FROM source_resolution s
    CROSS JOIN existing_counts c
    LEFT JOIN existing_payor_hers h ON 1 = 1
    WHERE s.source_status = 'RESOLVED'
    GROUP BY c.existing_payor_her_count, s.source_electronic_rec_guid
),
current_her AS (
    SELECT h.*
    FROM current_guid g
    JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = g.electronic_rec_guid
),
current_hefs AS (
    SELECT f.*
    FROM current_guid g
    JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = g.electronic_rec_guid
),
her_functional_match AS (
    SELECT CASE WHEN COUNT(*) = 1
        AND MIN(DECODE(c.loop_id, s.loop_id, 1, 0)) = 1
        AND MIN(DECODE(c.contiguity_ind, s.contiguity_ind, 1, 0)) = 1
        AND MIN(DECODE(c.billing_form_code, s.billing_form_code, 1, 0)) = 1
        AND MIN(DECODE(c.record_type_code, s.record_type_code, 1, 0)) = 1
        AND MIN(DECODE(c.record_size, s.record_size, 1, 0)) = 1
        AND MIN(DECODE(c.mandatory_ind, s.mandatory_ind, 1, 0)) = 1
        AND MIN(DECODE(c.req_for_claim_ind, s.req_for_claim_ind, 1, 0)) = 1
        AND MIN(DECODE(c.type_of_bill, s.type_of_bill, 1, 0)) = 1
        AND MIN(DECODE(c.detail_ind, s.detail_ind, 1, 0)) = 1
        AND MIN(DECODE(c.max_number, s.max_number, 1, 0)) = 1
        AND MIN(DECODE(c.invoice_ind, s.invoice_ind, 1, 0)) = 1
        AND MIN(DECODE(c.max_carry_forward, s.max_carry_forward, 1, 0)) = 1
        AND MIN(DECODE(c.sto_proc_name, s.sto_proc_name, 1, 0)) = 1
        THEN 1 ELSE 0 END AS is_match
    FROM current_her c
    CROSS JOIN source_resolution r
    JOIN hcfa_electronic_records s
      ON s.electronic_rec_guid = r.source_electronic_rec_guid
),
hef_functional_difference AS (
    SELECT COUNT(*) AS difference_count
    FROM (
        (SELECT field_number, field_name, record_type_code, sto_proc_name,
            pic, field_spec, position_from, position_thru, field_name_desc,
            mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
            occurs_next, hard_coded_data, field_format, caps_ind,
            required_subelement_ind, include_data_onclaim
         FROM current_hefs
         MINUS
         SELECT field_number, field_name, record_type_code, sto_proc_name,
            pic, field_spec, position_from, position_thru, field_name_desc,
            mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
            occurs_next, hard_coded_data, field_format, caps_ind,
            required_subelement_ind, include_data_onclaim
         FROM source_hefs)
        UNION ALL
        (SELECT field_number, field_name, record_type_code, sto_proc_name,
            pic, field_spec, position_from, position_thru, field_name_desc,
            mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
            occurs_next, hard_coded_data, field_format, caps_ind,
            required_subelement_ind, include_data_onclaim
         FROM source_hefs
         MINUS
         SELECT field_number, field_name, record_type_code, sto_proc_name,
            pic, field_spec, position_from, position_thru, field_name_desc,
            mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
            occurs_next, hard_coded_data, field_format, caps_ind,
            required_subelement_ind, include_data_onclaim
         FROM current_hefs)
    )
),
functional_equivalence AS (
    SELECT CASE WHEN h.is_match = 1 AND f.difference_count = 0
        THEN 1 ELSE 0 END AS is_equivalent
    FROM her_functional_match h
    CROSS JOIN hef_functional_difference f
),
current_managed AS (
    SELECT
        m.field_number,
        COUNT(f.electronic_rec_guid) AS match_count,
        MAX(f.sto_proc_name) AS sto_proc_name,
        MAX(f.hard_coded_data) AS hard_coded_data
    FROM managed_fields m
    LEFT JOIN current_hefs f ON f.field_number = m.field_number
    GROUP BY m.field_number
),
current_pivot AS (
    SELECT
        MAX(h.sto_proc_name) AS her_sto_proc_name,
        MAX(CASE WHEN m.field_number = '012' THEN m.match_count END) AS count_012,
        MAX(CASE WHEN m.field_number = '012' THEN m.sto_proc_name END) AS sto_012,
        MAX(CASE WHEN m.field_number = '012' THEN m.hard_coded_data END) AS hard_012,
        MAX(CASE WHEN m.field_number = '015' THEN m.match_count END) AS count_015,
        MAX(CASE WHEN m.field_number = '015' THEN m.sto_proc_name END) AS sto_015,
        MAX(CASE WHEN m.field_number = '015' THEN m.hard_coded_data END) AS hard_015,
        MAX(CASE WHEN m.field_number = '022' THEN m.match_count END) AS count_022,
        MAX(CASE WHEN m.field_number = '022' THEN m.sto_proc_name END) AS sto_022,
        MAX(CASE WHEN m.field_number = '022' THEN m.hard_coded_data END) AS hard_022,
        MAX(CASE WHEN m.field_number = '025' THEN m.match_count END) AS count_025,
        MAX(CASE WHEN m.field_number = '025' THEN m.sto_proc_name END) AS sto_025,
        MAX(CASE WHEN m.field_number = '025' THEN m.hard_coded_data END) AS hard_025
    FROM current_managed m
    LEFT JOIN current_her h ON 1 = 1
),
recipes AS (
    SELECT 'HOME_HEALTH' AS line_of_business,
        'HOME_HEALTH_CBSA' AS recipe_id, 'RETURN_1' AS her_proc,
        CAST(NULL AS VARCHAR2(30)) AS sto_012, '61' AS hard_012,
        'GET_PAT_CBSA_CODE' AS sto_015, CAST(NULL AS VARCHAR2(128)) AS hard_015,
        'GET_VAL_CODE' AS sto_022, CAST(NULL AS VARCHAR2(128)) AS hard_022,
        'GET_VAL_CODE_AMT' AS sto_025, CAST(NULL AS VARCHAR2(128)) AS hard_025
    FROM dual
    UNION ALL SELECT 'HOME_HEALTH', 'HOME_HEALTH_CBSA_FIPS', 'RETURN_1',
        NULL, '61', 'GET_PAT_CBSA_CODE', NULL,
        'GET_FIPS_CODE', NULL, 'GET_FIPS_CODE_VALUE', NULL FROM dual
    UNION ALL SELECT 'HOSPICE', 'HOSPICE_61_G8', 'RETURN_1',
        'GET_CARE_LOC_CODE', NULL, 'GET_CARE_LOC_VAL_CODE', NULL,
        'GET_VAL_CODE', NULL, 'GET_VAL_CODE_AMT', NULL FROM dual
    UNION ALL SELECT 'HOSPICE', 'HOSPICE_61_G8_VC80_DAYS', 'RETURN_1',
        NULL, '61', 'GET_PAT_CBSA_CODE', NULL,
        NULL, '80', 'GET_DISTINCT_COVERED_DAYS', NULL FROM dual
    UNION ALL SELECT 'HOSPICE', 'HOSPICE_PATIENT_VALUE', 'RETURN_1',
        'GET_VAL_CODE', NULL, 'GET_VAL_CODE_AMT', NULL,
        'GET_VAL_CODE', NULL, 'GET_VAL_CODE_AMT', NULL FROM dual
    UNION ALL SELECT 'HOSPICE', 'HOSPICE_PATIENT_VALUE_VC80_DAYS', 'RETURN_1',
        'GET_VAL_CODE', NULL, 'GET_VAL_CODE_AMT', NULL,
        NULL, '80', 'GET_DISTINCT_COVERED_DAYS', NULL FROM dual
    UNION ALL SELECT 'HOSPICE', 'HOSPICE_VC80_DAYS', 'RETURN_1',
        NULL, '80', 'GET_DISTINCT_COVERED_DAYS', NULL,
        'GET_VAL_CODE', NULL, 'GET_VAL_CODE_AMT', NULL FROM dual
),
recipe_matches AS (
    SELECT r.recipe_id
    FROM recipes r
    CROSS JOIN lob_resolution l
    CROSS JOIN current_pivot c
    WHERE r.line_of_business = l.line_of_business
      AND c.count_012 = 1 AND c.count_015 = 1
      AND c.count_022 = 1 AND c.count_025 = 1
      AND DECODE(c.her_sto_proc_name, r.her_proc, 1, 0) = 1
      AND DECODE(c.sto_012, r.sto_012, 1, 0) = 1
      AND DECODE(c.hard_012, r.hard_012, 1, 0) = 1
      AND DECODE(c.sto_015, r.sto_015, 1, 0) = 1
      AND DECODE(c.hard_015, r.hard_015, 1, 0) = 1
      AND DECODE(c.sto_022, r.sto_022, 1, 0) = 1
      AND DECODE(c.hard_022, r.hard_022, 1, 0) = 1
      AND DECODE(c.sto_025, r.sto_025, 1, 0) = 1
      AND DECODE(c.hard_025, r.hard_025, 1, 0) = 1
),
recognition AS (
    SELECT
        COUNT(*) AS recipe_match_count,
        CASE
            WHEN COUNT(*) = 0 THEN 'UNRECOGNIZED'
            WHEN COUNT(*) > 1 THEN 'AMBIGUOUS'
            ELSE MAX(recipe_id)
        END AS recognized_recipe
    FROM recipe_matches
),
summary AS (
    SELECT
        s.payor_guid,
        l.line_of_business,
        s.pfc_status,
        s.pfc_guid,
        s.payor_type_guid,
        s.billing_form_code,
        s.source_status,
        s.source_electronic_rec_guid,
        s.source_form_template_guid,
        s.source_user_form_template_guid,
        s.source_her_sto_proc_name,
        (SELECT COUNT(*) FROM source_hefs) AS source_hef_count,
        c.existing_payor_her_count,
        c.existing_payor_hef_count,
        CASE
            WHEN l.lob_status <> 'RESOLVED' THEN l.lob_status
            WHEN s.pfc_status = 'MISSING' THEN 'BLOCKED_PFC_MISSING'
            WHEN s.pfc_status <> 'RESOLVED' THEN 'BLOCKED_PFC_AMBIGUOUS'
            WHEN s.source_status = 'MISSING' THEN 'BLOCKED_SOURCE_MISSING'
            WHEN s.source_status <> 'RESOLVED' THEN 'BLOCKED_SOURCE_AMBIGUOUS'
            WHEN c.existing_payor_her_count > 1
                THEN 'BLOCKED_DUPLICATE_PAYOR_HER'
            WHEN c.existing_payor_her_count = 0 THEN 'RESOLVED'
            WHEN e.is_equivalent = 1 THEN 'RESOLVED'
            WHEN r.recipe_match_count = 0 THEN 'UNRECOGNIZED'
            WHEN r.recipe_match_count > 1 THEN 'AMBIGUOUS'
            ELSE 'RESOLVED'
        END AS current_effective_status,
        CASE
            WHEN c.existing_payor_her_count = 0 THEN 'DEFAULT'
            WHEN c.existing_payor_her_count = 1 AND e.is_equivalent = 1
                THEN 'DEFAULT'
            ELSE r.recognized_recipe
        END AS current_recognized_recipe
    FROM source_resolution s
    CROSS JOIN lob_resolution l
    CROSS JOIN existing_counts c
    CROSS JOIN functional_equivalence e
    CROSS JOIN recognition r
),
diagnostic_rows AS (
    SELECT
        'SOURCE_MANAGED' AS output_section,
        m.field_order AS section_order,
        h.electronic_rec_guid, h.payor_guid AS her_payor_guid,
        h.payor_type_guid AS her_payor_type_guid, h.plan_guid AS her_plan_guid,
        h.type_of_bill AS her_type_of_bill,
        h.form_template_guid AS her_form_template_guid,
        h.user_form_template_guid AS her_user_form_template_guid,
        h.sto_proc_name AS her_sto_proc_name,
        m.field_number, f.field_name, f.record_type_code AS hef_record_type_code,
        f.sto_proc_name, f.hard_coded_data,
        f.pic, f.field_spec, f.position_from, f.position_thru,
        f.field_name_desc, f.mandatory_ind, f.must_fit_length_ind,
        f.order_num, f.repeats, f.detail_ind, f.occurs_next, f.field_format,
        f.caps_ind, f.required_subelement_ind, f.include_data_onclaim,
        f.rec_ent_date, f.rec_ent_user, f.rec_mod_date, f.rec_mod_user
    FROM managed_fields m
    CROSS JOIN source_resolution s
    LEFT JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = s.source_electronic_rec_guid
    LEFT JOIN source_hefs f ON f.field_number = m.field_number
    UNION ALL
    SELECT
        'CURRENT_EFFECTIVE_MANAGED', 10 + m.field_order,
        h.electronic_rec_guid, h.payor_guid, h.payor_type_guid, h.plan_guid,
        h.type_of_bill, h.form_template_guid, h.user_form_template_guid,
        h.sto_proc_name,
        m.field_number, f.field_name, f.record_type_code,
        f.sto_proc_name, f.hard_coded_data,
        f.pic, f.field_spec, f.position_from, f.position_thru,
        f.field_name_desc, f.mandatory_ind, f.must_fit_length_ind,
        f.order_num, f.repeats, f.detail_ind, f.occurs_next, f.field_format,
        f.caps_ind, f.required_subelement_ind, f.include_data_onclaim,
        f.rec_ent_date, f.rec_ent_user, f.rec_mod_date, f.rec_mod_user
    FROM managed_fields m
    LEFT JOIN current_hefs f ON f.field_number = m.field_number
    LEFT JOIN current_her h ON 1 = 1
    UNION ALL
    SELECT
        'SOURCE_COMPLETE', 100 + ROW_NUMBER() OVER (
            ORDER BY f.order_num, f.field_number),
        h.electronic_rec_guid, h.payor_guid, h.payor_type_guid, h.plan_guid,
        h.type_of_bill, h.form_template_guid, h.user_form_template_guid,
        h.sto_proc_name,
        f.field_number, f.field_name, f.record_type_code,
        f.sto_proc_name, f.hard_coded_data,
        f.pic, f.field_spec, f.position_from, f.position_thru,
        f.field_name_desc, f.mandatory_ind, f.must_fit_length_ind,
        f.order_num, f.repeats, f.detail_ind, f.occurs_next, f.field_format,
        f.caps_ind, f.required_subelement_ind, f.include_data_onclaim,
        f.rec_ent_date, f.rec_ent_user, f.rec_mod_date, f.rec_mod_user
    FROM source_hefs f
    JOIN source_resolution s ON 1 = 1
    JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = s.source_electronic_rec_guid
    UNION ALL
    SELECT
        'CURRENT_EFFECTIVE_COMPLETE', 1000 + ROW_NUMBER() OVER (
            ORDER BY f.order_num, f.field_number),
        h.electronic_rec_guid, h.payor_guid, h.payor_type_guid, h.plan_guid,
        h.type_of_bill, h.form_template_guid, h.user_form_template_guid,
        h.sto_proc_name,
        f.field_number, f.field_name, f.record_type_code,
        f.sto_proc_name, f.hard_coded_data,
        f.pic, f.field_spec, f.position_from, f.position_thru,
        f.field_name_desc, f.mandatory_ind, f.must_fit_length_ind,
        f.order_num, f.repeats, f.detail_ind, f.occurs_next, f.field_format,
        f.caps_ind, f.required_subelement_ind, f.include_data_onclaim,
        f.rec_ent_date, f.rec_ent_user, f.rec_mod_date, f.rec_mod_user
    FROM current_hefs f
    JOIN current_her h ON 1 = 1
)
SELECT
    'SUMMARY' AS output_section,
    0 AS output_order,
    s.payor_guid,
    s.line_of_business,
    s.pfc_status,
    s.pfc_guid,
    s.payor_type_guid,
    s.billing_form_code,
    s.source_status,
    s.source_electronic_rec_guid,
    s.source_form_template_guid,
    s.source_user_form_template_guid,
    s.source_her_sto_proc_name,
    s.source_hef_count,
    s.existing_payor_her_count,
    s.existing_payor_hef_count,
    s.current_effective_status,
    s.current_recognized_recipe,
    CAST(NULL AS VARCHAR2(36)) AS row_electronic_rec_guid,
    CAST(NULL AS VARCHAR2(36)) AS row_her_payor_guid,
    CAST(NULL AS VARCHAR2(36)) AS row_her_payor_type_guid,
    CAST(NULL AS VARCHAR2(36)) AS row_her_plan_guid,
    CAST(NULL AS VARCHAR2(3)) AS row_her_type_of_bill,
    CAST(NULL AS VARCHAR2(36)) AS row_her_form_template_guid,
    CAST(NULL AS VARCHAR2(36)) AS row_her_user_template_guid,
    CAST(NULL AS VARCHAR2(30)) AS row_her_sto_proc_name,
    CAST(NULL AS VARCHAR2(10)) AS field_number,
    CAST(NULL AS VARCHAR2(50)) AS field_name,
    CAST(NULL AS VARCHAR2(20)) AS hef_record_type_code,
    CAST(NULL AS VARCHAR2(30)) AS sto_proc_name,
    CAST(NULL AS VARCHAR2(128)) AS hard_coded_data,
    CAST(NULL AS VARCHAR2(50)) AS pic,
    CAST(NULL AS VARCHAR2(1)) AS field_spec,
    CAST(NULL AS NUMBER) AS position_from,
    CAST(NULL AS NUMBER) AS position_thru,
    CAST(NULL AS VARCHAR2(2000)) AS field_name_desc,
    CAST(NULL AS VARCHAR2(1)) AS mandatory_ind,
    CAST(NULL AS VARCHAR2(1)) AS must_fit_length_ind,
    CAST(NULL AS NUMBER) AS order_num,
    CAST(NULL AS NUMBER) AS repeats,
    CAST(NULL AS VARCHAR2(1)) AS detail_ind,
    CAST(NULL AS VARCHAR2(10)) AS occurs_next,
    CAST(NULL AS VARCHAR2(128)) AS field_format,
    CAST(NULL AS VARCHAR2(1)) AS caps_ind,
    CAST(NULL AS VARCHAR2(1)) AS required_subelement_ind,
    CAST(NULL AS VARCHAR2(1)) AS include_data_onclaim,
    CAST(NULL AS DATE) AS rec_ent_date,
    CAST(NULL AS VARCHAR2(36)) AS rec_ent_user,
    CAST(NULL AS DATE) AS rec_mod_date,
    CAST(NULL AS VARCHAR2(36)) AS rec_mod_user
FROM summary s
UNION ALL
SELECT
    d.output_section,
    d.section_order,
    s.payor_guid, s.line_of_business, s.pfc_status, s.pfc_guid,
    s.payor_type_guid, s.billing_form_code, s.source_status,
    s.source_electronic_rec_guid, s.source_form_template_guid,
    s.source_user_form_template_guid, s.source_her_sto_proc_name,
    s.source_hef_count, s.existing_payor_her_count,
    s.existing_payor_hef_count, s.current_effective_status,
    s.current_recognized_recipe,
    d.electronic_rec_guid, d.her_payor_guid, d.her_payor_type_guid,
    d.her_plan_guid, d.her_type_of_bill, d.her_form_template_guid,
    d.her_user_form_template_guid, d.her_sto_proc_name,
    d.field_number, d.field_name, d.hef_record_type_code,
    d.sto_proc_name, d.hard_coded_data,
    d.pic, d.field_spec, d.position_from, d.position_thru,
    d.field_name_desc, d.mandatory_ind, d.must_fit_length_ind,
    d.order_num, d.repeats, d.detail_ind, d.occurs_next, d.field_format,
    d.caps_ind, d.required_subelement_ind, d.include_data_onclaim,
    d.rec_ent_date, d.rec_ent_user, d.rec_mod_date, d.rec_mod_user
FROM diagnostic_rows d
CROSS JOIN summary s
ORDER BY output_order;
