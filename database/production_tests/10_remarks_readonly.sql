/*
 * UB-04 Field 80 Remarks production current-state inspection (READ_ONLY).
 *
 * Edit PAYOR_GUID, PLAN_GUID, and LINE_OF_BUSINESS only in manual_inputs.
 * Leave PLAN_GUID NULL for payor-level resolution; replace the CAST expression
 * with a plan GUID literal to test a plan. LINE_OF_BUSINESS is tool-only
 * metadata and must be HOME_HEALTH or HOSPICE. This standalone statement uses
 * MatrixCare production objects only and reads production data only. Run it
 * normally in Toad and save the complete result grid.
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
    SELECT TRIM(payor_guid) payor_guid, TRIM(plan_guid) plan_guid,
           UPPER(TRIM(line_of_business)) line_of_business,
           'D23001900NTE182' record_type_code
    FROM manual_inputs
),
managed_fields AS (
    SELECT '00' field_number, 'NTE00' field_name, 1 field_order FROM dual
    UNION ALL SELECT '01', 'NTE01', 2 FROM dual
    UNION ALL SELECT '02', 'NTE02', 3 FROM dual
),
lob_resolution AS (
    SELECT p.*,
           CASE WHEN line_of_business IN ('HOME_HEALTH', 'HOSPICE')
                THEN 'RESOLVED' ELSE 'BLOCKED_LOB_INVALID' END lob_status
    FROM params p
),
eligible_pfc AS (
    SELECT p.*, y.payor_type_guid,
           DENSE_RANK() OVER (ORDER BY p.cpd_start_date DESC NULLS LAST) pfc_rank
    FROM pfc p
    JOIN payors y ON y.payor_guid = p.payor_guid
    CROSS JOIN params x
    WHERE p.payor_guid = x.payor_guid
      AND p.cpd_end_date > SYSDATE
      AND p.default_media_type = 'E'
      AND p.type_of_bill IS NULL
      AND ((x.plan_guid IS NULL AND p.plan_guid IS NULL)
        OR (x.plan_guid IS NOT NULL
            AND (p.plan_guid = x.plan_guid OR p.plan_guid IS NULL)))
),
winning_pfc AS (
    SELECT * FROM eligible_pfc WHERE pfc_rank = 1
),
pfc_resolution AS (
    SELECT x.payor_guid, x.plan_guid requested_plan_guid,
           x.line_of_business, x.lob_status, x.record_type_code,
           CASE WHEN COUNT(w.pfc_guid) = 0 THEN 'MISSING'
                WHEN COUNT(w.pfc_guid) > 1 THEN 'AMBIGUOUS_NEWEST_DATE'
                ELSE 'RESOLVED' END pfc_status,
           CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.pfc_guid) END pfc_guid,
           CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.plan_guid) END pfc_plan_guid,
           CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.payor_type_guid) END payor_type_guid,
           CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.billing_form_code) END billing_form_code,
           CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.form_template_guid) END form_template_guid,
           CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.user_form_template_guid) END user_form_template_guid
    FROM lob_resolution x LEFT JOIN winning_pfc w ON 1 = 1
    GROUP BY x.payor_guid, x.plan_guid, x.line_of_business, x.lob_status,
             x.record_type_code
),
source_candidates AS (
    SELECT h.*,
           CASE WHEN h.user_form_template_guid IS NOT NULL THEN 1
                WHEN h.form_template_guid IS NOT NULL THEN 2 ELSE 3 END template_rank,
           CASE WHEN h.payor_type_guid = p.payor_type_guid
                     AND h.payor_type_guid IS NOT NULL THEN 1 ELSE 2 END type_rank
    FROM pfc_resolution p
    JOIN hcfa_electronic_records h
      ON h.billing_form_code = p.billing_form_code
     AND h.record_type_code = p.record_type_code
    WHERE p.pfc_status = 'RESOLVED'
      AND h.payor_guid IS NULL AND h.plan_guid IS NULL
      AND h.type_of_bill IS NULL
      AND (h.payor_type_guid = p.payor_type_guid OR h.payor_type_guid IS NULL)
      AND ((h.user_form_template_guid IS NOT NULL
            AND h.user_form_template_guid = p.user_form_template_guid)
        OR (h.user_form_template_guid IS NULL
            AND h.form_template_guid IS NOT NULL
            AND h.form_template_guid = p.form_template_guid)
        OR (h.user_form_template_guid IS NULL AND h.form_template_guid IS NULL))
),
ranked_sources AS (
    SELECT s.*, DENSE_RANK() OVER (
        ORDER BY template_rank, type_rank) source_rank
    FROM source_candidates s
),
source_resolution AS (
    SELECT p.*,
           CASE WHEN p.pfc_status <> 'RESOLVED' THEN 'BLOCKED_PFC'
                WHEN COUNT(s.electronic_rec_guid) = 0 THEN 'MISSING'
                WHEN COUNT(s.electronic_rec_guid) > 1 THEN 'AMBIGUOUS'
                ELSE 'RESOLVED' END source_status,
           CASE WHEN COUNT(s.electronic_rec_guid) = 1
                THEN MAX(s.electronic_rec_guid) END source_electronic_rec_guid,
           CASE WHEN COUNT(s.electronic_rec_guid) = 1 THEN
                MAX(CASE s.template_rank WHEN 1 THEN 'USER_TEMPLATE'
                    WHEN 2 THEN 'FORM_TEMPLATE' ELSE 'BILLING_FORM' END) END source_template_level,
           CASE WHEN COUNT(s.electronic_rec_guid) = 1
                THEN MAX(s.sto_proc_name) END source_her_sto_proc_name,
           CASE WHEN COUNT(s.electronic_rec_guid) = 1
                THEN MAX(s.mandatory_ind) END source_her_mandatory_ind
    FROM pfc_resolution p
    LEFT JOIN ranked_sources s ON s.source_rank = 1
    GROUP BY p.payor_guid, p.requested_plan_guid, p.line_of_business,
             p.lob_status, p.record_type_code, p.pfc_status, p.pfc_guid,
             p.pfc_plan_guid, p.payor_type_guid, p.billing_form_code,
             p.form_template_guid, p.user_form_template_guid
),
source_hefs AS (
    SELECT f.* FROM source_resolution s
    JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = s.source_electronic_rec_guid
    WHERE s.source_status = 'RESOLVED'
),
payor_hers AS (
    SELECT h.* FROM source_resolution s
    JOIN hcfa_electronic_records h
      ON h.payor_guid = s.payor_guid
     AND h.billing_form_code = s.billing_form_code
     AND h.record_type_code = s.record_type_code
),
counts AS (
    SELECT COUNT(DISTINCT h.electronic_rec_guid) existing_payor_her_count,
           COUNT(f.electronic_rec_guid) existing_payor_hef_count
    FROM payor_hers h LEFT JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
),
current_guid AS (
    SELECT CASE WHEN c.existing_payor_her_count = 0
                     THEN s.source_electronic_rec_guid
                WHEN c.existing_payor_her_count = 1
                     THEN MAX(h.electronic_rec_guid) END electronic_rec_guid
    FROM source_resolution s CROSS JOIN counts c
    LEFT JOIN payor_hers h ON 1 = 1
    GROUP BY c.existing_payor_her_count, s.source_electronic_rec_guid
),
current_her AS (
    SELECT h.* FROM current_guid g JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = g.electronic_rec_guid
),
current_hefs AS (
    SELECT f.* FROM current_guid g JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = g.electronic_rec_guid
),
her_equal AS (
    SELECT CASE WHEN COUNT(*) = 1
      AND MIN(DECODE(c.loop_id, b.loop_id, 1, 0)) = 1
      AND MIN(DECODE(c.contiguity_ind, b.contiguity_ind, 1, 0)) = 1
      AND MIN(DECODE(c.billing_form_code, b.billing_form_code, 1, 0)) = 1
      AND MIN(DECODE(c.record_type_code, b.record_type_code, 1, 0)) = 1
      AND MIN(DECODE(c.record_size, b.record_size, 1, 0)) = 1
      AND MIN(DECODE(c.mandatory_ind, b.mandatory_ind, 1, 0)) = 1
      AND MIN(DECODE(c.req_for_claim_ind, b.req_for_claim_ind, 1, 0)) = 1
      AND MIN(DECODE(c.type_of_bill, b.type_of_bill, 1, 0)) = 1
      AND MIN(DECODE(c.detail_ind, b.detail_ind, 1, 0)) = 1
      AND MIN(DECODE(c.max_number, b.max_number, 1, 0)) = 1
      AND MIN(DECODE(c.invoice_ind, b.invoice_ind, 1, 0)) = 1
      AND MIN(DECODE(c.max_carry_forward, b.max_carry_forward, 1, 0)) = 1
      AND MIN(DECODE(c.sto_proc_name, b.sto_proc_name, 1, 0)) = 1
      THEN 1 ELSE 0 END is_equal
    FROM current_her c CROSS JOIN source_resolution s
    JOIN hcfa_electronic_records b
      ON b.electronic_rec_guid = s.source_electronic_rec_guid
),
hef_diff AS (
    SELECT COUNT(*) difference_count FROM (
      (SELECT field_number, field_name, record_type_code, sto_proc_name, pic,
          field_spec, position_from, position_thru, field_name_desc,
          mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
          occurs_next, hard_coded_data, field_format, caps_ind,
          required_subelement_ind, include_data_onclaim FROM current_hefs
       MINUS
       SELECT field_number, field_name, record_type_code, sto_proc_name, pic,
          field_spec, position_from, position_thru, field_name_desc,
          mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
          occurs_next, hard_coded_data, field_format, caps_ind,
          required_subelement_ind, include_data_onclaim FROM source_hefs)
      UNION ALL
      (SELECT field_number, field_name, record_type_code, sto_proc_name, pic,
          field_spec, position_from, position_thru, field_name_desc,
          mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
          occurs_next, hard_coded_data, field_format, caps_ind,
          required_subelement_ind, include_data_onclaim FROM source_hefs
       MINUS
       SELECT field_number, field_name, record_type_code, sto_proc_name, pic,
          field_spec, position_from, position_thru, field_name_desc,
          mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
          occurs_next, hard_coded_data, field_format, caps_ind,
          required_subelement_ind, include_data_onclaim FROM current_hefs)
    )
),
managed_current AS (
    SELECT m.field_number, m.field_name, m.field_order,
           COUNT(f.electronic_rec_guid) match_count,
           MAX(f.sto_proc_name) sto_proc_name,
           MAX(f.hard_coded_data) hard_coded_data
    FROM managed_fields m LEFT JOIN current_hefs f
      ON f.field_number = m.field_number AND f.field_name = m.field_name
    GROUP BY m.field_number, m.field_name, m.field_order
),
current_remark AS (
    SELECT MAX(CASE WHEN field_number = '02' THEN hard_coded_data END)
               custom_remark
    FROM managed_current
),
custom_hefs AS (
    SELECT field_number, field_name, record_type_code,
           CASE WHEN (field_number = '00' AND field_name = 'NTE00')
                  OR (field_number = '01' AND field_name = 'NTE01')
                  OR (field_number = '02' AND field_name = 'NTE02')
                THEN NULL ELSE sto_proc_name END sto_proc_name,
           pic, field_spec, position_from, position_thru, field_name_desc,
           mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
           occurs_next,
           CASE WHEN field_number = '00' AND field_name = 'NTE00' THEN 'NTE'
                WHEN field_number = '01' AND field_name = 'NTE01' THEN 'ADD'
                WHEN field_number = '02' AND field_name = 'NTE02'
                    THEN r.custom_remark
                ELSE hard_coded_data END hard_coded_data,
           field_format, caps_ind, required_subelement_ind,
           include_data_onclaim
    FROM source_hefs CROSS JOIN current_remark r
),
custom_hef_diff AS (
    SELECT COUNT(*) difference_count FROM (
      (SELECT field_number, field_name, record_type_code, sto_proc_name, pic,
          field_spec, position_from, position_thru, field_name_desc,
          mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
          occurs_next, hard_coded_data, field_format, caps_ind,
          required_subelement_ind, include_data_onclaim FROM current_hefs
       MINUS
       SELECT field_number, field_name, record_type_code, sto_proc_name, pic,
          field_spec, position_from, position_thru, field_name_desc,
          mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
          occurs_next, hard_coded_data, field_format, caps_ind,
          required_subelement_ind, include_data_onclaim FROM custom_hefs)
      UNION ALL
      (SELECT field_number, field_name, record_type_code, sto_proc_name, pic,
          field_spec, position_from, position_thru, field_name_desc,
          mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
          occurs_next, hard_coded_data, field_format, caps_ind,
          required_subelement_ind, include_data_onclaim FROM custom_hefs
       MINUS
       SELECT field_number, field_name, record_type_code, sto_proc_name, pic,
          field_spec, position_from, position_thru, field_name_desc,
          mandatory_ind, must_fit_length_ind, order_num, repeats, detail_ind,
          occurs_next, hard_coded_data, field_format, caps_ind,
          required_subelement_ind, include_data_onclaim FROM current_hefs)
    )
),
custom_her_equal AS (
    SELECT CASE WHEN COUNT(*) = 1
      AND MIN(DECODE(c.loop_id, b.loop_id, 1, 0)) = 1
      AND MIN(DECODE(c.contiguity_ind, b.contiguity_ind, 1, 0)) = 1
      AND MIN(DECODE(c.billing_form_code, b.billing_form_code, 1, 0)) = 1
      AND MIN(DECODE(c.record_name, b.record_name, 1, 0)) = 1
      AND MIN(DECODE(c.record_type_code, b.record_type_code, 1, 0)) = 1
      AND MIN(DECODE(c.record_size, b.record_size, 1, 0)) = 1
      AND MIN(DECODE(c.mandatory_ind, b.mandatory_ind, 1, 0)) = 1
      AND MIN(DECODE(c.req_for_claim_ind, b.req_for_claim_ind, 1, 0)) = 1
      AND MIN(CASE WHEN c.payor_type_guid IS NULL
                        OR c.payor_type_guid = s.payor_type_guid THEN 1 ELSE 0 END) = 1
      AND MIN(DECODE(c.payor_guid, s.payor_guid, 1, 0)) = 1
      AND MIN(DECODE(c.plan_guid, b.plan_guid, 1, 0)) = 1
      AND MIN(DECODE(c.type_of_bill, b.type_of_bill, 1, 0)) = 1
      AND MIN(DECODE(c.detail_ind, b.detail_ind, 1, 0)) = 1
      AND MIN(DECODE(c.max_number, b.max_number, 1, 0)) = 1
      AND MIN(DECODE(c.invoice_ind, b.invoice_ind, 1, 0)) = 1
      AND MIN(DECODE(c.form_template_guid, b.form_template_guid, 1, 0)) = 1
      AND MIN(CASE WHEN c.carry_forward_ind IS NULL THEN 1 ELSE 0 END) = 1
      AND MIN(DECODE(c.max_carry_forward, b.max_carry_forward, 1, 0)) = 1
      AND MIN(CASE WHEN c.sto_proc_name = 'RETURN_1' THEN 1 ELSE 0 END) = 1
      AND MIN(DECODE(c.user_form_template_guid,
                     b.user_form_template_guid, 1, 0)) = 1
      AND MIN(DECODE(c.notes, b.notes, 1, 0)) = 1
      AND MIN(CASE WHEN c.include_record_data_onclaim = 'Y' THEN 1 ELSE 0 END) = 1
      THEN 1 ELSE 0 END is_equal
    FROM current_her c CROSS JOIN source_resolution s
    JOIN hcfa_electronic_records b
      ON b.electronic_rec_guid = s.source_electronic_rec_guid
),
recognition AS (
    SELECT CASE
      WHEN c.existing_payor_her_count = 0 THEN 'DEFAULT'
      WHEN c.existing_payor_her_count > 1 THEN 'UNRECOGNIZED'
      WHEN h.is_equal = 1 AND d.difference_count = 0 THEN 'DEFAULT'
      WHEN ch.is_equal = 1 AND cd.difference_count = 0
       AND (SELECT sto_proc_name FROM current_her) = 'RETURN_1'
       AND SUM(CASE WHEN m.field_number = '00' AND m.match_count = 1
                     AND m.sto_proc_name IS NULL AND m.hard_coded_data = 'NTE'
                    THEN 1 ELSE 0 END) = 1
       AND SUM(CASE WHEN m.field_number = '01' AND m.match_count = 1
                     AND m.sto_proc_name IS NULL AND m.hard_coded_data = 'ADD'
                    THEN 1 ELSE 0 END) = 1
       AND SUM(CASE WHEN m.field_number = '02' AND m.match_count = 1
                     AND m.sto_proc_name IS NULL
                     AND TRIM(m.hard_coded_data) IS NOT NULL
                     AND LENGTH(m.hard_coded_data) <= 100
                    THEN 1 ELSE 0 END) = 1 THEN 'CUSTOM'
      ELSE 'UNRECOGNIZED' END current_mode,
      MAX(CASE WHEN m.field_number = '02' THEN m.hard_coded_data END) current_custom_remark
    FROM counts c CROSS JOIN her_equal h CROSS JOIN hef_diff d
    CROSS JOIN custom_her_equal ch CROSS JOIN custom_hef_diff cd
    CROSS JOIN managed_current m
    GROUP BY c.existing_payor_her_count, h.is_equal, d.difference_count,
             ch.is_equal, cd.difference_count
),
summary AS (
    SELECT s.*, c.existing_payor_her_count, c.existing_payor_hef_count,
           (SELECT COUNT(*) FROM source_hefs) source_hef_count,
           CASE WHEN s.lob_status <> 'RESOLVED' THEN s.lob_status
                WHEN s.pfc_status <> 'RESOLVED' THEN 'BLOCKED_PFC'
                WHEN s.source_status = 'MISSING' THEN 'BLOCKED_SOURCE_MISSING'
                WHEN s.source_status <> 'RESOLVED' THEN 'BLOCKED_SOURCE_AMBIGUOUS'
                WHEN NVL(UPPER(TRIM(s.source_her_sto_proc_name)), '<NULL>') <>
                        'RETURN_1'
                 AND NVL(UPPER(TRIM(s.source_her_mandatory_ind)), '<NULL>') <>
                        'N'
                    THEN 'BLOCKED_SOURCE_INVALID_MANDATORY'
                WHEN c.existing_payor_her_count > 1
                    THEN 'BLOCKED_DUPLICATE_PAYOR_HER'
                WHEN c.existing_payor_her_count = 1
                 AND EXISTS (SELECT 1 FROM current_her h
                     WHERE NVL(UPPER(TRIM(h.sto_proc_name)), '<NULL>') <>
                            'RETURN_1'
                       AND NVL(UPPER(TRIM(h.mandatory_ind)), '<NULL>') <> 'N')
                    THEN 'UNRECOGNIZED'
                WHEN r.current_mode = 'UNRECOGNIZED' THEN 'UNRECOGNIZED'
                ELSE 'RESOLVED' END status,
           r.current_mode,
           CASE WHEN r.current_mode = 'CUSTOM'
                THEN r.current_custom_remark END current_custom_remark
    FROM source_resolution s CROSS JOIN counts c CROSS JOIN recognition r
)
SELECT 'SUMMARY' output_section, 0 output_order,
       s.status, s.line_of_business, s.current_mode,
       s.current_custom_remark, s.payor_guid, s.requested_plan_guid plan_guid,
       s.pfc_guid, s.payor_type_guid, s.billing_form_code,
       s.record_type_code, s.source_status, s.source_electronic_rec_guid,
       s.source_template_level, s.source_her_sto_proc_name,
       s.source_her_mandatory_ind,
       CASE WHEN s.source_status <> 'RESOLVED' THEN 'UNAVAILABLE'
            WHEN NVL(UPPER(TRIM(s.source_her_sto_proc_name)), '<NULL>') = 'RETURN_1'
                  OR NVL(UPPER(TRIM(s.source_her_mandatory_ind)), '<NULL>') = 'N'
            THEN 'SAFE' ELSE 'INVALID_MANDATORY_COMBINATION' END source_safety_status,
       (SELECT sto_proc_name FROM current_her) current_her_sto_proc_name,
       (SELECT mandatory_ind FROM current_her) current_her_mandatory_ind,
       s.source_hef_count, s.existing_payor_her_count,
       s.existing_payor_hef_count,
       CAST(NULL AS VARCHAR2(10)) field_number,
       CAST(NULL AS VARCHAR2(50)) field_name,
       CAST(NULL AS VARCHAR2(30)) source_sto_proc_name,
       CAST(NULL AS VARCHAR2(128)) source_hard_coded_data,
       CAST(NULL AS VARCHAR2(30)) current_sto_proc_name,
       CAST(NULL AS VARCHAR2(128)) current_hard_coded_data
FROM summary s
UNION ALL
SELECT 'MANAGED_FIELD', 10 + m.field_order,
       s.status, s.line_of_business, s.current_mode,
       s.current_custom_remark, s.payor_guid, s.requested_plan_guid,
       s.pfc_guid, s.payor_type_guid, s.billing_form_code,
       s.record_type_code, s.source_status, s.source_electronic_rec_guid,
       s.source_template_level, s.source_her_sto_proc_name,
       s.source_her_mandatory_ind,
       CASE WHEN s.source_status <> 'RESOLVED' THEN 'UNAVAILABLE'
            WHEN NVL(UPPER(TRIM(s.source_her_sto_proc_name)), '<NULL>') = 'RETURN_1'
                  OR NVL(UPPER(TRIM(s.source_her_mandatory_ind)), '<NULL>') = 'N'
            THEN 'SAFE' ELSE 'INVALID_MANDATORY_COMBINATION' END,
       (SELECT sto_proc_name FROM current_her),
       (SELECT mandatory_ind FROM current_her),
       s.source_hef_count, s.existing_payor_her_count,
       s.existing_payor_hef_count,
       m.field_number, m.field_name, sf.sto_proc_name,
       sf.hard_coded_data, cf.sto_proc_name, cf.hard_coded_data
FROM summary s CROSS JOIN managed_fields m
LEFT JOIN source_hefs sf
  ON sf.field_number = m.field_number AND sf.field_name = m.field_name
LEFT JOIN current_hefs cf
  ON cf.field_number = m.field_number AND cf.field_name = m.field_name
ORDER BY output_order;
