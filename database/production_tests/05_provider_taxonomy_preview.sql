/*
 * Provider Taxonomy production PREVIEW using the final generic PFC rules.
 *
 * Edit the three literals in manual_inputs, then run this statement in Toad.
 * To request a plan, replace CAST(NULL AS VARCHAR2(36)) with 'the-plan-guid'.
 * PROVIDER_TAXONOMY must be ON or OFF. The statement installs nothing and
 * changes no data. Invalid input or ambiguous production state returns a
 * BLOCKED row.
 */
WITH manual_inputs AS (
    SELECT
        'PUT_PAYOR_GUID_HERE' AS payor_guid,
        CAST(NULL AS VARCHAR2(36)) AS plan_guid,
        'ON' AS provider_taxonomy
    FROM dual
),
params AS (
    SELECT
        TRIM(payor_guid) AS payor_guid,
        TRIM(plan_guid) AS plan_guid,
        UPPER(TRIM(provider_taxonomy)) AS provider_taxonomy,
        CASE
            WHEN TRIM(payor_guid) IS NULL
              OR TRIM(payor_guid) = 'PUT_PAYOR_GUID_HERE'
                THEN 'PAYOR_GUID_REQUIRED'
            WHEN UPPER(TRIM(provider_taxonomy)) NOT IN ('ON', 'OFF')
                THEN 'INVALID_PROVIDER_TAXONOMY'
            ELSE 'VALID'
        END AS input_status,
        CASE
            WHEN UPPER(TRIM(provider_taxonomy)) = 'ON'
                THEN 'PROVIDER_TAXONOMY_ON'
            WHEN UPPER(TRIM(provider_taxonomy)) = 'OFF'
                THEN 'PROVIDER_TAXONOMY_OFF'
        END AS option_code
    FROM manual_inputs
),
targets AS (
    SELECT
        1 AS target_order,
        'PRV' AS target_segment,
        'B2000A0030PRV080' AS record_type_code
    FROM dual
),
requested_targets AS (
    SELECT
        t.*,
        p.payor_guid,
        p.plan_guid AS requested_plan_guid,
        p.provider_taxonomy,
        p.input_status,
        p.option_code,
        CASE
            WHEN p.provider_taxonomy = 'ON' THEN 'RETURN_1'
            WHEN p.provider_taxonomy = 'OFF' THEN 'RETURN_0'
        END AS desired_her_sto_proc_name,
        CASE
            WHEN p.provider_taxonomy = 'ON' THEN 'Y'
            ELSE 'N'
        END AS target_active
    FROM targets t
    CROSS JOIN params p
),
requested_overlays AS (
    SELECT 'PRV' AS target_segment, '03' AS field_number,
           'PRV03' AS field_name,
           'SET' AS sto_action,
           'G_PROVIDER_TAXONOMY_CODE' AS desired_sto_proc_name,
           CAST(NULL AS VARCHAR2(10)) AS hard_action,
           CAST(NULL AS VARCHAR2(4000)) AS desired_hard_coded_data
    FROM params p
    WHERE p.provider_taxonomy IN ('ON', 'OFF')
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
    WHERE x.input_status = 'VALID'
      AND p.payor_guid = x.payor_guid
      AND p.cpd_end_date > SYSDATE
      AND p.default_media_type = 'E'
      AND p.type_of_bill IS NULL
      AND (
            (x.plan_guid IS NULL AND p.plan_guid IS NULL)
            OR
            (x.plan_guid IS NOT NULL AND (
                p.plan_guid = x.plan_guid
                OR p.plan_guid IS NULL
            ))
          )
),
winning_pfc AS (
    SELECT e.*
    FROM eligible_pfc e
    WHERE e.start_date_rank = 1
),
pfc_resolution AS (
    SELECT
        p.*,
        CASE
            WHEN p.input_status <> 'VALID' THEN 'BLOCKED_INVALID_INPUT'
            WHEN COUNT(w.pfc_guid) = 0 THEN 'MISSING'
            WHEN COUNT(w.pfc_guid) > 1 THEN 'AMBIGUOUS_NEWEST_DATE'
            ELSE 'RESOLVED'
        END AS pfc_status,
        COUNT(w.pfc_guid) AS winning_pfc_count,
        CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.pfc_guid) END AS pfc_guid,
        CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.plan_guid) END
            AS pfc_plan_guid,
        CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.payor_type_guid) END
            AS payor_type_guid,
        CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.billing_form_code) END
            AS billing_form_code,
        CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.form_template_guid) END
            AS pfc_form_template_guid,
        CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.user_form_template_guid) END
            AS pfc_user_form_template_guid,
        CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.cpd_start_date) END
            AS cpd_start_date,
        CASE WHEN COUNT(w.pfc_guid) = 1 THEN MAX(w.cpd_end_date) END
            AS cpd_end_date
    FROM params p
    LEFT JOIN winning_pfc w
      ON 1 = 1
    GROUP BY
        p.payor_guid,
        p.plan_guid,
        p.provider_taxonomy,
        p.input_status,
        p.option_code
),
target_context AS (
    SELECT
        r.*,
        p.pfc_status,
        p.winning_pfc_count,
        p.pfc_guid,
        p.pfc_plan_guid,
        p.payor_type_guid,
        p.billing_form_code,
        p.pfc_form_template_guid,
        p.pfc_user_form_template_guid,
        p.cpd_start_date,
        p.cpd_end_date
    FROM requested_targets r
    CROSS JOIN pfc_resolution p
),
source_candidates AS (
    SELECT
        c.target_segment,
        h.*,
        CASE
            WHEN h.user_form_template_guid IS NOT NULL THEN 1
            WHEN h.form_template_guid IS NOT NULL THEN 2
            ELSE 3
        END AS template_rank,
        CASE
            WHEN h.payor_type_guid = c.payor_type_guid
             AND h.payor_type_guid IS NOT NULL THEN 1
            ELSE 2
        END AS payor_type_rank
    FROM target_context c
    JOIN hcfa_electronic_records h
      ON h.billing_form_code = c.billing_form_code
     AND h.record_type_code = c.record_type_code
    WHERE c.pfc_status = 'RESOLVED'
      AND h.payor_guid IS NULL
      AND h.plan_guid IS NULL
      AND h.type_of_bill IS NULL
      AND (h.payor_type_guid = c.payor_type_guid
           OR h.payor_type_guid IS NULL)
      AND (
            (h.user_form_template_guid IS NOT NULL
             AND c.pfc_user_form_template_guid IS NOT NULL
             AND h.user_form_template_guid = c.pfc_user_form_template_guid
             AND (h.form_template_guid = c.pfc_form_template_guid
                  OR h.form_template_guid IS NULL))
            OR
            (h.user_form_template_guid IS NULL
             AND h.form_template_guid IS NOT NULL
             AND c.pfc_form_template_guid IS NOT NULL
             AND h.form_template_guid = c.pfc_form_template_guid)
            OR
            (h.user_form_template_guid IS NULL
             AND h.form_template_guid IS NULL)
          )
),
ranked_source_candidates AS (
    SELECT
        s.*,
        DENSE_RANK() OVER (
            PARTITION BY s.target_segment
            ORDER BY s.template_rank, s.payor_type_rank
        ) AS source_rank
    FROM source_candidates s
),
best_source_candidates AS (
    SELECT s.*
    FROM ranked_source_candidates s
    WHERE s.source_rank = 1
),
source_counts AS (
    SELECT
        c.target_segment,
        COUNT(s.electronic_rec_guid) AS best_source_count
    FROM target_context c
    LEFT JOIN best_source_candidates s
      ON s.target_segment = c.target_segment
    GROUP BY c.target_segment
),
source_resolution AS (
    SELECT
        c.*,
        n.best_source_count,
        CASE
            WHEN c.pfc_status <> 'RESOLVED' THEN 'BLOCKED_BY_PFC'
            WHEN n.best_source_count = 0 THEN 'MISSING'
            WHEN n.best_source_count > 1 THEN 'AMBIGUOUS'
            ELSE 'RESOLVED'
        END AS source_status,
        CASE WHEN n.best_source_count = 1
            THEN MAX(s.electronic_rec_guid) END
            AS source_electronic_rec_guid,
        CASE WHEN n.best_source_count = 1
            THEN MAX(s.sto_proc_name) END AS source_her_sto_proc_name,
        CASE WHEN n.best_source_count = 1
            THEN MAX(s.form_template_guid) END AS source_form_template_guid,
        CASE WHEN n.best_source_count = 1
            THEN MAX(s.user_form_template_guid) END
            AS source_user_form_template_guid,
        CASE WHEN n.best_source_count = 1
            THEN MAX(s.payor_type_guid) END AS source_payor_type_guid
    FROM target_context c
    JOIN source_counts n
      ON n.target_segment = c.target_segment
    LEFT JOIN best_source_candidates s
      ON s.target_segment = c.target_segment
    GROUP BY
        c.target_order,
        c.target_segment,
        c.record_type_code,
        c.payor_guid,
        c.requested_plan_guid,
        c.provider_taxonomy,
        c.input_status,
        c.option_code,
        c.desired_her_sto_proc_name,
        c.target_active,
        c.pfc_status,
        c.winning_pfc_count,
        c.pfc_guid,
        c.pfc_plan_guid,
        c.payor_type_guid,
        c.billing_form_code,
        c.pfc_form_template_guid,
        c.pfc_user_form_template_guid,
        c.cpd_start_date,
        c.cpd_end_date,
        n.best_source_count
),
resolved_source_hers AS (
    SELECT
        s.target_order,
        h.*
    FROM source_resolution s
    JOIN best_source_candidates h
      ON h.target_segment = s.target_segment
     AND h.electronic_rec_guid = s.source_electronic_rec_guid
    WHERE s.source_status = 'RESOLVED'
),
source_hefs AS (
    SELECT
        s.target_order,
        s.target_segment,
        f.*
    FROM source_resolution s
    JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = s.source_electronic_rec_guid
    WHERE s.source_status = 'RESOLVED'
),
overlay_matches AS (
    SELECT
        o.target_segment,
        o.field_number,
        COUNT(f.electronic_rec_guid) AS source_match_count
    FROM requested_overlays o
    LEFT JOIN source_hefs f
      ON f.target_segment = o.target_segment
     AND f.field_number = o.field_number
     AND f.field_name = o.field_name
    GROUP BY o.target_segment, o.field_number, o.field_name
),
overlay_validation AS (
    SELECT
        c.target_segment,
        NVL(SUM(CASE WHEN m.source_match_count = 0 THEN 1 ELSE 0 END), 0)
            AS missing_overlay_hef_count,
        NVL(SUM(CASE WHEN m.source_match_count > 1 THEN 1 ELSE 0 END), 0)
            AS ambiguous_overlay_hef_count
    FROM target_context c
    LEFT JOIN overlay_matches m
      ON m.target_segment = c.target_segment
    GROUP BY c.target_segment
),
desired_hefs AS (
    SELECT
        f.target_order,
        f.target_segment,
        f.field_number,
        f.field_name,
        f.record_type_code,
        CASE
            WHEN o.hard_action = 'SET'
             AND o.desired_hard_coded_data IS NOT NULL THEN NULL
            WHEN o.sto_action = 'SET' THEN o.desired_sto_proc_name
            WHEN o.sto_action = 'CLEAR' THEN NULL
            ELSE f.sto_proc_name
        END
            AS sto_proc_name,
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
        CASE
            WHEN o.sto_action = 'SET'
             AND o.desired_sto_proc_name IS NOT NULL THEN NULL
            WHEN o.hard_action = 'SET' THEN o.desired_hard_coded_data
            WHEN o.hard_action = 'CLEAR' THEN NULL
            ELSE f.hard_coded_data
        END
            AS hard_coded_data,
        f.field_format,
        f.caps_ind,
        f.required_subelement_ind,
        f.include_data_onclaim
    FROM source_hefs f
    LEFT JOIN requested_overlays o
      ON o.target_segment = f.target_segment
     AND o.field_number = f.field_number
     AND o.field_name = f.field_name
),
source_desired_delta AS (
    SELECT
        s.target_segment,
        SUM(CASE
            WHEN DECODE(s.sto_proc_name, d.sto_proc_name, 1, 0) = 0
              OR DECODE(s.hard_coded_data, d.hard_coded_data, 1, 0) = 0
                THEN 1 ELSE 0
        END) AS changed_hef_count
    FROM source_hefs s
    JOIN desired_hefs d
      ON d.target_segment = s.target_segment
     AND d.field_number = s.field_number
     AND d.field_name = s.field_name
     AND d.position_from = s.position_from
     AND d.position_thru = s.position_thru
     AND DECODE(d.order_num, s.order_num, 1, 0) = 1
    GROUP BY s.target_segment
),
source_desired_status AS (
    SELECT
        s.target_segment,
        CASE
            WHEN s.source_status <> 'RESOLVED' THEN 'N'
            WHEN v.missing_overlay_hef_count > 0
              OR v.ambiguous_overlay_hef_count > 0 THEN 'N'
            WHEN DECODE(
                    s.source_her_sto_proc_name,
                    s.desired_her_sto_proc_name,
                    1,
                    0
                 ) = 1
             AND NVL(d.changed_hef_count, 0) = 0 THEN 'Y'
            ELSE 'N'
        END AS source_equals_desired
    FROM source_resolution s
    JOIN overlay_validation v
      ON v.target_segment = s.target_segment
    LEFT JOIN source_desired_delta d
      ON d.target_segment = s.target_segment
),
current_payor_hers AS (
    SELECT
        c.target_order,
        c.target_segment,
        h.*
    FROM target_context c
    JOIN hcfa_electronic_records h
      ON h.payor_guid = c.payor_guid
     AND h.billing_form_code = c.billing_form_code
     AND h.record_type_code = c.record_type_code
    WHERE c.pfc_status = 'RESOLVED'
),
current_payor_hefs AS (
    SELECT
        h.target_order,
        h.target_segment,
        f.*
    FROM current_payor_hers h
    JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
),
current_counts AS (
    SELECT
        c.target_segment,
        COUNT(DISTINCT h.electronic_rec_guid) AS existing_payor_her_count,
        COUNT(f.electronic_rec_guid) AS existing_payor_hef_count
    FROM target_context c
    LEFT JOIN current_payor_hers h
      ON h.target_segment = c.target_segment
    LEFT JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
    GROUP BY c.target_segment
),
current_her_validation AS (
    SELECT
        s.target_segment,
        CASE
            WHEN n.existing_payor_her_count <> 1 THEN 0
            WHEN DECODE(h.loop_id, src.loop_id, 1, 0) = 1
             AND DECODE(h.contiguity_ind, src.contiguity_ind, 1, 0) = 1
             AND DECODE(h.billing_form_code, src.billing_form_code, 1, 0) = 1
             AND DECODE(h.record_name, src.record_name, 1, 0) = 1
             AND DECODE(h.record_type_code, src.record_type_code, 1, 0) = 1
             AND DECODE(h.record_size, src.record_size, 1, 0) = 1
             AND DECODE(h.mandatory_ind, src.mandatory_ind, 1, 0) = 1
             AND DECODE(h.req_for_claim_ind, src.req_for_claim_ind, 1, 0) = 1
             AND (h.payor_type_guid = s.payor_type_guid
                  OR h.payor_type_guid IS NULL)
             AND DECODE(h.payor_guid, s.payor_guid, 1, 0) = 1
             AND DECODE(h.plan_guid, src.plan_guid, 1, 0) = 1
             AND DECODE(h.type_of_bill, src.type_of_bill, 1, 0) = 1
             AND DECODE(h.detail_ind, src.detail_ind, 1, 0) = 1
             AND DECODE(h.max_number, src.max_number, 1, 0) = 1
             AND DECODE(h.invoice_ind, src.invoice_ind, 1, 0) = 1
             AND DECODE(
                    h.form_template_guid,
                    src.form_template_guid,
                    1,
                    0
                 ) = 1
             AND h.carry_forward_ind IS NULL
             AND DECODE(h.max_carry_forward, src.max_carry_forward, 1, 0) = 1
             AND DECODE(
                    h.sto_proc_name,
                    s.desired_her_sto_proc_name,
                    1,
                    0
                 ) = 1
             AND DECODE(
                    h.user_form_template_guid,
                    src.user_form_template_guid,
                    1,
                    0
                 ) = 1
             AND DECODE(h.notes, src.notes, 1, 0) = 1
             AND DECODE(h.include_record_data_onclaim, 'Y', 1, 0) = 1
                THEN 1
            ELSE 0
        END AS her_matches_desired,
        CASE WHEN n.existing_payor_her_count = 1
              AND DECODE(
                    h.sto_proc_name,
                    s.desired_her_sto_proc_name,
                    1,
                    0
                  ) = 0 THEN 1 ELSE 0 END AS her_sto_mismatch_count,
        CASE WHEN n.existing_payor_her_count = 1
              AND h.payor_type_guid IS NOT NULL
              AND h.payor_type_guid <> s.payor_type_guid
            THEN 1 ELSE 0 END AS her_payor_type_mismatch_count,
        CASE WHEN n.existing_payor_her_count = 1 THEN
            RTRIM(
                CASE WHEN DECODE(h.loop_id, src.loop_id, 1, 0) = 0
                    THEN 'LOOP_ID; ' END ||
                CASE WHEN DECODE(
                        h.contiguity_ind,
                        src.contiguity_ind,
                        1,
                        0
                    ) = 0 THEN 'CONTIGUITY_IND; ' END ||
                CASE WHEN DECODE(
                        h.billing_form_code,
                        src.billing_form_code,
                        1,
                        0
                    ) = 0 THEN 'BILLING_FORM_CODE; ' END ||
                CASE WHEN DECODE(h.record_name, src.record_name, 1, 0) = 0
                    THEN 'RECORD_NAME; ' END ||
                CASE WHEN DECODE(
                        h.record_type_code,
                        src.record_type_code,
                        1,
                        0
                    ) = 0 THEN 'RECORD_TYPE_CODE; ' END ||
                CASE WHEN DECODE(h.record_size, src.record_size, 1, 0) = 0
                    THEN 'RECORD_SIZE; ' END ||
                CASE WHEN DECODE(
                        h.mandatory_ind,
                        src.mandatory_ind,
                        1,
                        0
                    ) = 0 THEN 'MANDATORY_IND; ' END ||
                CASE WHEN DECODE(
                        h.req_for_claim_ind,
                        src.req_for_claim_ind,
                        1,
                        0
                    ) = 0 THEN 'REQ_FOR_CLAIM_IND; ' END ||
                CASE WHEN h.payor_type_guid IS NOT NULL
                           AND h.payor_type_guid <> s.payor_type_guid
                    THEN 'PAYOR_TYPE_GUID; ' END ||
                CASE WHEN DECODE(h.payor_guid, s.payor_guid, 1, 0) = 0
                    THEN 'PAYOR_GUID; ' END ||
                CASE WHEN DECODE(h.plan_guid, src.plan_guid, 1, 0) = 0
                    THEN 'PLAN_GUID; ' END ||
                CASE WHEN DECODE(
                        h.type_of_bill,
                        src.type_of_bill,
                        1,
                        0
                    ) = 0 THEN 'TYPE_OF_BILL; ' END ||
                CASE WHEN DECODE(h.detail_ind, src.detail_ind, 1, 0) = 0
                    THEN 'DETAIL_IND; ' END ||
                CASE WHEN DECODE(h.max_number, src.max_number, 1, 0) = 0
                    THEN 'MAX_NUMBER; ' END ||
                CASE WHEN DECODE(h.invoice_ind, src.invoice_ind, 1, 0) = 0
                    THEN 'INVOICE_IND; ' END ||
                CASE WHEN DECODE(
                        h.form_template_guid,
                        src.form_template_guid,
                        1,
                        0
                    ) = 0 THEN 'FORM_TEMPLATE_GUID; ' END ||
                CASE WHEN h.carry_forward_ind IS NOT NULL
                    THEN 'CARRY_FORWARD_IND; ' END ||
                CASE WHEN DECODE(
                        h.max_carry_forward,
                        src.max_carry_forward,
                        1,
                        0
                    ) = 0 THEN 'MAX_CARRY_FORWARD; ' END ||
                CASE WHEN DECODE(
                        h.sto_proc_name,
                        s.desired_her_sto_proc_name,
                        1,
                        0
                    ) = 0 THEN 'STO_PROC_NAME; ' END ||
                CASE WHEN DECODE(
                        h.user_form_template_guid,
                        src.user_form_template_guid,
                        1,
                        0
                    ) = 0 THEN 'USER_FORM_TEMPLATE_GUID; ' END ||
                CASE WHEN DECODE(h.notes, src.notes, 1, 0) = 0
                    THEN 'NOTES; ' END ||
                CASE WHEN DECODE(
                        h.include_record_data_onclaim,
                        'Y',
                        1,
                        0
                    ) = 0 THEN 'INCLUDE_RECORD_DATA_ONCLAIM; ' END,
                '; '
            )
        END AS her_attribute_mismatch_detail,
        h.electronic_rec_guid AS current_her_electronic_rec_guid,
        src.loop_id AS source_her_loop_id,
        h.loop_id AS current_her_loop_id,
        src.contiguity_ind AS source_her_contiguity_ind,
        h.contiguity_ind AS current_her_contiguity_ind,
        src.billing_form_code AS source_her_billing_form_code,
        h.billing_form_code AS current_her_billing_form_code,
        src.record_name AS source_her_record_name,
        h.record_name AS current_her_record_name,
        src.record_type_code AS source_her_record_type_code,
        h.record_type_code AS current_her_record_type_code,
        src.record_size AS source_her_record_size,
        h.record_size AS current_her_record_size,
        src.mandatory_ind AS source_her_mandatory_ind,
        h.mandatory_ind AS current_her_mandatory_ind,
        src.req_for_claim_ind AS source_her_req_for_claim_ind,
        h.req_for_claim_ind AS current_her_req_for_claim_ind,
        src.payor_type_guid AS source_her_payor_type_guid,
        h.payor_type_guid AS current_her_payor_type_guid,
        s.payor_type_guid AS desired_her_payor_type_guid,
        src.payor_guid AS source_her_payor_guid,
        h.payor_guid AS current_her_payor_guid,
        s.payor_guid AS desired_her_payor_guid,
        src.plan_guid AS source_her_plan_guid,
        h.plan_guid AS current_her_plan_guid,
        src.plan_guid AS desired_her_plan_guid,
        src.type_of_bill AS source_her_type_of_bill,
        h.type_of_bill AS current_her_type_of_bill,
        src.type_of_bill AS desired_her_type_of_bill,
        src.detail_ind AS source_her_detail_ind,
        h.detail_ind AS current_her_detail_ind,
        src.max_number AS source_her_max_number,
        h.max_number AS current_her_max_number,
        src.invoice_ind AS source_her_invoice_ind,
        h.invoice_ind AS current_her_invoice_ind,
        src.form_template_guid AS source_her_form_template_guid,
        h.form_template_guid AS current_her_form_template_guid,
        src.form_template_guid AS desired_her_form_template_guid,
        src.carry_forward_ind AS source_her_carry_forward_ind,
        h.carry_forward_ind AS current_her_carry_forward_ind,
        CAST(NULL AS VARCHAR2(1)) AS desired_her_carry_forward_ind,
        src.max_carry_forward AS source_her_max_carry_forward,
        h.max_carry_forward AS current_her_max_carry_forward,
        h.sto_proc_name AS current_her_sto_proc_name,
        src.user_form_template_guid AS source_her_user_form_template_guid,
        h.user_form_template_guid AS current_her_user_form_template_guid,
        src.user_form_template_guid AS desired_her_user_form_template_guid,
        src.notes AS source_her_notes,
        h.notes AS current_her_notes,
        src.include_record_data_onclaim AS source_her_include_onclaim,
        h.include_record_data_onclaim AS current_her_include_onclaim,
        'Y' AS desired_her_include_onclaim
    FROM source_resolution s
    JOIN current_counts n
      ON n.target_segment = s.target_segment
    LEFT JOIN current_payor_hers h
      ON h.target_segment = s.target_segment
     AND n.existing_payor_her_count = 1
    LEFT JOIN resolved_source_hers src
      ON src.target_segment = s.target_segment
),
desired_hef_signatures AS (
    SELECT
        d.target_segment,
        RAWTOHEX(STANDARD_HASH(
            NVL(d.field_number, CHR(0)) || CHR(31) ||
            NVL(d.field_name, CHR(0)) || CHR(31) ||
            NVL(d.record_type_code, CHR(0)) || CHR(31) ||
            NVL(d.sto_proc_name, CHR(0)) || CHR(31) ||
            NVL(d.pic, CHR(0)) || CHR(31) ||
            NVL(d.field_spec, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.position_from, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.position_thru, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(d.field_name_desc, CHR(0)) || CHR(31) ||
            NVL(d.mandatory_ind, CHR(0)) || CHR(31) ||
            NVL(d.must_fit_length_ind, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.order_num, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.repeats, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(d.detail_ind, CHR(0)) || CHR(31) ||
            NVL(d.occurs_next, CHR(0)) || CHR(31) ||
            NVL(d.hard_coded_data, CHR(0)) || CHR(31) ||
            NVL(d.field_format, CHR(0)) || CHR(31) ||
            NVL(d.caps_ind, CHR(0)) || CHR(31) ||
            NVL(d.required_subelement_ind, CHR(0)) || CHR(31) ||
            NVL(d.include_data_onclaim, CHR(0)),
            'SHA256'
        )) AS row_signature,
        COUNT(*) AS row_count
    FROM desired_hefs d
    GROUP BY
        d.target_segment,
        RAWTOHEX(STANDARD_HASH(
            NVL(d.field_number, CHR(0)) || CHR(31) ||
            NVL(d.field_name, CHR(0)) || CHR(31) ||
            NVL(d.record_type_code, CHR(0)) || CHR(31) ||
            NVL(d.sto_proc_name, CHR(0)) || CHR(31) ||
            NVL(d.pic, CHR(0)) || CHR(31) ||
            NVL(d.field_spec, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.position_from, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.position_thru, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(d.field_name_desc, CHR(0)) || CHR(31) ||
            NVL(d.mandatory_ind, CHR(0)) || CHR(31) ||
            NVL(d.must_fit_length_ind, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.order_num, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.repeats, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(d.detail_ind, CHR(0)) || CHR(31) ||
            NVL(d.occurs_next, CHR(0)) || CHR(31) ||
            NVL(d.hard_coded_data, CHR(0)) || CHR(31) ||
            NVL(d.field_format, CHR(0)) || CHR(31) ||
            NVL(d.caps_ind, CHR(0)) || CHR(31) ||
            NVL(d.required_subelement_ind, CHR(0)) || CHR(31) ||
            NVL(d.include_data_onclaim, CHR(0)),
            'SHA256'
        ))
),
current_hef_signatures AS (
    SELECT
        f.target_segment,
        RAWTOHEX(STANDARD_HASH(
            NVL(f.field_number, CHR(0)) || CHR(31) ||
            NVL(f.field_name, CHR(0)) || CHR(31) ||
            NVL(f.record_type_code, CHR(0)) || CHR(31) ||
            NVL(f.sto_proc_name, CHR(0)) || CHR(31) ||
            NVL(f.pic, CHR(0)) || CHR(31) ||
            NVL(f.field_spec, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.position_from, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.position_thru, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(f.field_name_desc, CHR(0)) || CHR(31) ||
            NVL(f.mandatory_ind, CHR(0)) || CHR(31) ||
            NVL(f.must_fit_length_ind, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.order_num, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.repeats, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(f.detail_ind, CHR(0)) || CHR(31) ||
            NVL(f.occurs_next, CHR(0)) || CHR(31) ||
            NVL(f.hard_coded_data, CHR(0)) || CHR(31) ||
            NVL(f.field_format, CHR(0)) || CHR(31) ||
            NVL(f.caps_ind, CHR(0)) || CHR(31) ||
            NVL(f.required_subelement_ind, CHR(0)) || CHR(31) ||
            NVL(f.include_data_onclaim, CHR(0)),
            'SHA256'
        )) AS row_signature,
        COUNT(*) AS row_count
    FROM current_payor_hefs f
    GROUP BY
        f.target_segment,
        RAWTOHEX(STANDARD_HASH(
            NVL(f.field_number, CHR(0)) || CHR(31) ||
            NVL(f.field_name, CHR(0)) || CHR(31) ||
            NVL(f.record_type_code, CHR(0)) || CHR(31) ||
            NVL(f.sto_proc_name, CHR(0)) || CHR(31) ||
            NVL(f.pic, CHR(0)) || CHR(31) ||
            NVL(f.field_spec, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.position_from, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.position_thru, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(f.field_name_desc, CHR(0)) || CHR(31) ||
            NVL(f.mandatory_ind, CHR(0)) || CHR(31) ||
            NVL(f.must_fit_length_ind, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.order_num, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.repeats, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(f.detail_ind, CHR(0)) || CHR(31) ||
            NVL(f.occurs_next, CHR(0)) || CHR(31) ||
            NVL(f.hard_coded_data, CHR(0)) || CHR(31) ||
            NVL(f.field_format, CHR(0)) || CHR(31) ||
            NVL(f.caps_ind, CHR(0)) || CHR(31) ||
            NVL(f.required_subelement_ind, CHR(0)) || CHR(31) ||
            NVL(f.include_data_onclaim, CHR(0)),
            'SHA256'
        ))
),
hef_signature_differences AS (
    SELECT
        COALESCE(d.target_segment, c.target_segment) AS target_segment,
        SUM(ABS(NVL(d.row_count, 0) - NVL(c.row_count, 0)))
            AS signature_difference_count
    FROM desired_hef_signatures d
    FULL OUTER JOIN current_hef_signatures c
      ON c.target_segment = d.target_segment
     AND c.row_signature = d.row_signature
    GROUP BY COALESCE(d.target_segment, c.target_segment)
),
desired_field_counts AS (
    SELECT target_segment, field_number, COUNT(*) AS field_count
    FROM desired_hefs
    GROUP BY target_segment, field_number
),
current_field_counts AS (
    SELECT target_segment, field_number, COUNT(*) AS field_count
    FROM current_payor_hefs
    GROUP BY target_segment, field_number
),
field_count_metrics AS (
    SELECT
        COALESCE(d.target_segment, c.target_segment) AS target_segment,
        SUM(CASE
            WHEN d.field_number IS NOT NULL
                THEN GREATEST(d.field_count - NVL(c.field_count, 0), 0)
            ELSE 0
        END) AS missing_hef_count,
        SUM(CASE
            WHEN d.field_number IS NOT NULL
                THEN GREATEST(NVL(c.field_count, 0) - d.field_count, 0)
            ELSE 0
        END) AS duplicate_hef_count,
        SUM(CASE WHEN d.field_number IS NULL
            THEN c.field_count ELSE 0 END) AS extra_hef_count
    FROM desired_field_counts d
    FULL OUTER JOIN current_field_counts c
      ON c.target_segment = d.target_segment
     AND c.field_number = d.field_number
    GROUP BY COALESCE(d.target_segment, c.target_segment)
),
hef_attribute_metrics AS (
    SELECT
        d.target_segment,
        SUM(CASE WHEN dc.field_count = 1 AND cc.field_count = 1
                  AND DECODE(d.sto_proc_name, c.sto_proc_name, 1, 0) = 0
            THEN 1 ELSE 0 END) AS hef_sto_mismatch_count,
        SUM(CASE WHEN dc.field_count = 1 AND cc.field_count = 1
                  AND DECODE(
                        d.hard_coded_data,
                        c.hard_coded_data,
                        1,
                        0
                      ) = 0
            THEN 1 ELSE 0 END) AS hef_hard_mismatch_count,
        SUM(CASE WHEN dc.field_count = 1 AND cc.field_count = 1
                  AND (
                    DECODE(d.field_name, c.field_name, 1, 0) = 0
                    OR DECODE(d.record_type_code, c.record_type_code, 1, 0) = 0
                    OR DECODE(d.pic, c.pic, 1, 0) = 0
                    OR DECODE(d.field_spec, c.field_spec, 1, 0) = 0
                    OR DECODE(d.position_from, c.position_from, 1, 0) = 0
                    OR DECODE(d.position_thru, c.position_thru, 1, 0) = 0
                    OR DECODE(d.field_name_desc, c.field_name_desc, 1, 0) = 0
                    OR DECODE(d.mandatory_ind, c.mandatory_ind, 1, 0) = 0
                    OR DECODE(
                        d.must_fit_length_ind,
                        c.must_fit_length_ind,
                        1,
                        0
                    ) = 0
                    OR DECODE(d.order_num, c.order_num, 1, 0) = 0
                    OR DECODE(d.repeats, c.repeats, 1, 0) = 0
                    OR DECODE(d.detail_ind, c.detail_ind, 1, 0) = 0
                    OR DECODE(d.occurs_next, c.occurs_next, 1, 0) = 0
                    OR DECODE(d.field_format, c.field_format, 1, 0) = 0
                    OR DECODE(d.caps_ind, c.caps_ind, 1, 0) = 0
                    OR DECODE(
                        d.required_subelement_ind,
                        c.required_subelement_ind,
                        1,
                        0
                    ) = 0
                    OR DECODE(
                        d.include_data_onclaim,
                        c.include_data_onclaim,
                        1,
                        0
                    ) = 0
                  )
            THEN 1 ELSE 0 END) AS hef_cloned_attribute_mismatch_count
    FROM desired_hefs d
    JOIN desired_field_counts dc
      ON dc.target_segment = d.target_segment
     AND dc.field_number = d.field_number
    LEFT JOIN current_field_counts cc
      ON cc.target_segment = d.target_segment
     AND cc.field_number = d.field_number
    LEFT JOIN current_payor_hefs c
      ON c.target_segment = d.target_segment
     AND c.field_number = d.field_number
     AND cc.field_count = 1
    GROUP BY d.target_segment
),
comparison_summary AS (
    SELECT
        s.*,
        v.missing_overlay_hef_count,
        v.ambiguous_overlay_hef_count,
        e.source_equals_desired,
        n.existing_payor_her_count,
        n.existing_payor_hef_count,
        NVL(h.her_matches_desired, 0) AS her_matches_desired,
        NVL(h.her_sto_mismatch_count, 0) AS her_sto_mismatch_count,
        NVL(h.her_payor_type_mismatch_count, 0)
            AS her_payor_type_mismatch_count,
        h.her_attribute_mismatch_detail,
        h.current_her_electronic_rec_guid,
        h.source_her_loop_id,
        h.current_her_loop_id,
        h.source_her_contiguity_ind,
        h.current_her_contiguity_ind,
        h.source_her_billing_form_code,
        h.current_her_billing_form_code,
        h.source_her_record_name,
        h.current_her_record_name,
        h.source_her_record_type_code,
        h.current_her_record_type_code,
        h.source_her_record_size,
        h.current_her_record_size,
        h.source_her_mandatory_ind,
        h.current_her_mandatory_ind,
        h.source_her_req_for_claim_ind,
        h.current_her_req_for_claim_ind,
        h.source_her_payor_type_guid,
        h.current_her_payor_type_guid,
        h.desired_her_payor_type_guid,
        h.source_her_payor_guid,
        h.current_her_payor_guid,
        h.desired_her_payor_guid,
        h.source_her_plan_guid,
        h.current_her_plan_guid,
        h.desired_her_plan_guid,
        h.source_her_type_of_bill,
        h.current_her_type_of_bill,
        h.desired_her_type_of_bill,
        h.source_her_detail_ind,
        h.current_her_detail_ind,
        h.source_her_max_number,
        h.current_her_max_number,
        h.source_her_invoice_ind,
        h.current_her_invoice_ind,
        h.source_her_form_template_guid,
        h.current_her_form_template_guid,
        h.desired_her_form_template_guid,
        h.source_her_carry_forward_ind,
        h.current_her_carry_forward_ind,
        h.desired_her_carry_forward_ind,
        h.source_her_max_carry_forward,
        h.current_her_max_carry_forward,
        h.current_her_sto_proc_name,
        h.source_her_user_form_template_guid,
        h.current_her_user_form_template_guid,
        h.desired_her_user_form_template_guid,
        h.source_her_notes,
        h.current_her_notes,
        h.source_her_include_onclaim,
        h.current_her_include_onclaim,
        h.desired_her_include_onclaim,
        NVL(f.missing_hef_count, 0) AS missing_hef_count,
        NVL(f.duplicate_hef_count, 0) AS duplicate_hef_count,
        NVL(f.extra_hef_count, 0) AS extra_hef_count,
        NVL(a.hef_sto_mismatch_count, 0) AS hef_sto_mismatch_count,
        NVL(a.hef_hard_mismatch_count, 0) AS hef_hard_mismatch_count,
        NVL(a.hef_cloned_attribute_mismatch_count, 0)
            AS hef_cloned_attribute_mismatch_count,
        NVL(d.signature_difference_count, 0) AS signature_difference_count,
        CASE
            WHEN n.existing_payor_her_count = 1
             AND NVL(h.her_matches_desired, 0) = 1
             AND NVL(d.signature_difference_count, 0) = 0 THEN 'Y'
            ELSE 'N'
        END AS current_matches_desired
    FROM source_resolution s
    JOIN overlay_validation v
      ON v.target_segment = s.target_segment
    JOIN source_desired_status e
      ON e.target_segment = s.target_segment
    JOIN current_counts n
      ON n.target_segment = s.target_segment
    LEFT JOIN current_her_validation h
      ON h.target_segment = s.target_segment
    LEFT JOIN field_count_metrics f
      ON f.target_segment = s.target_segment
    LEFT JOIN hef_attribute_metrics a
      ON a.target_segment = s.target_segment
    LEFT JOIN hef_signature_differences d
      ON d.target_segment = s.target_segment
),
target_decisions AS (
    SELECT
        c.*,
        CASE
            WHEN c.input_status <> 'VALID'
              OR c.pfc_status <> 'RESOLVED'
              OR c.source_status <> 'RESOLVED'
              OR c.missing_overlay_hef_count > 0
              OR c.ambiguous_overlay_hef_count > 0 THEN 'BLOCKED'
            WHEN c.source_equals_desired = 'Y'
             AND c.existing_payor_her_count = 0 THEN 'NO_CHANGE'
            WHEN c.source_equals_desired = 'Y'
             AND c.existing_payor_her_count > 0 THEN 'REMOVE_OVERRIDE'
            WHEN c.source_equals_desired = 'N'
             AND c.current_matches_desired = 'Y' THEN 'NO_CHANGE'
            ELSE 'REBUILD_OVERRIDE'
        END AS target_action,
        RTRIM(
            CASE WHEN c.input_status <> 'VALID'
                THEN 'invalid input: ' || c.input_status || '; ' END ||
            CASE WHEN c.pfc_status <> 'RESOLVED'
                THEN 'PFC ' || LOWER(c.pfc_status) || '; ' END ||
            CASE WHEN c.source_status <> 'RESOLVED'
                THEN 'unresolved source: ' || LOWER(c.source_status) || '; ' END ||
            CASE WHEN c.source_status = 'RESOLVED'
                       AND c.missing_overlay_hef_count > 0
                THEN 'missing source overlay HEF; ' END ||
            CASE WHEN c.source_status = 'RESOLVED'
                       AND c.ambiguous_overlay_hef_count > 0
                THEN 'duplicate source overlay HEF; ' END ||
            CASE WHEN c.source_equals_desired = 'Y'
                       AND c.existing_payor_her_count > 0
                THEN 'source already desired; payor override is unnecessary; '
            END ||
            CASE WHEN c.source_status = 'RESOLVED'
                       AND c.missing_overlay_hef_count = 0
                       AND c.ambiguous_overlay_hef_count = 0
                       AND c.source_equals_desired = 'N'
                       AND c.existing_payor_her_count = 0
                THEN 'missing payor HER; ' END ||
            CASE WHEN c.source_status = 'RESOLVED'
                       AND c.source_equals_desired = 'N'
                       AND c.existing_payor_her_count > 1
                THEN 'duplicate payor HER; ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.her_sto_mismatch_count > 0
                THEN 'HER STO_PROC mismatch; ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.her_payor_type_mismatch_count > 0
                THEN 'HER PAYOR_TYPE mismatch; ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.existing_payor_her_count = 1
                       AND c.her_matches_desired = 0
                THEN 'HER attribute mismatch: ' ||
                    NVL(c.her_attribute_mismatch_detail, 'UNIDENTIFIED') ||
                    '; ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.missing_hef_count > 0
                THEN 'missing HEF (' || c.missing_hef_count || '); ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.duplicate_hef_count > 0
                THEN 'duplicate HEF (' || c.duplicate_hef_count || '); ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.extra_hef_count > 0
                THEN 'extra HEF (' || c.extra_hef_count || '); ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.hef_sto_mismatch_count > 0
                THEN 'HEF STO_PROC mismatch (' ||
                    c.hef_sto_mismatch_count || '); ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.hef_hard_mismatch_count > 0
                THEN 'HEF hard-coded-data mismatch (' ||
                    c.hef_hard_mismatch_count || '); ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.hef_cloned_attribute_mismatch_count > 0
                THEN 'other cloned HEF attribute mismatch (' ||
                    c.hef_cloned_attribute_mismatch_count || '); ' END ||
            CASE WHEN c.source_equals_desired = 'Y'
                       AND c.existing_payor_her_count = 0
                THEN 'inherited source already matches desired; ' END ||
            CASE WHEN c.source_equals_desired = 'N'
                       AND c.current_matches_desired = 'Y'
                THEN 'existing payor configuration matches desired; ' END,
            '; '
        ) AS diagnostic_reason
    FROM comparison_summary c
),
overall_result AS (
    SELECT
        CASE
            WHEN SUM(CASE WHEN target_action = 'BLOCKED' THEN 1 ELSE 0 END) > 0
                THEN 'BLOCKED'
            WHEN SUM(CASE WHEN target_action = 'NO_CHANGE' THEN 1 ELSE 0 END) = 1
                THEN 'NO_CHANGE'
            ELSE 'CHANGES_REQUIRED'
        END AS overall_action,
        CASE
            WHEN SUM(CASE WHEN target_action = 'BLOCKED' THEN 1 ELSE 0 END) > 0
                THEN 'BLOCKED'
            WHEN SUM(CASE WHEN target_action = 'NO_CHANGE' THEN 1 ELSE 0 END) = 1
                THEN 'NO_CHANGE'
            ELSE 'PREVIEW_READY'
        END AS overall_status
    FROM target_decisions
),
state_atoms_raw AS (
    SELECT
        0 AS atom_group,
        0 AS target_order,
        'CONTEXT' AS sort_value_1,
        'CONTEXT' AS sort_value_2,
        'CONTEXT|' || NVL(p.option_code, '<NULL>') || '|' ||
        NVL(p.payor_guid, '<NULL>') || '|' ||
        NVL(p.plan_guid, '<NULL>') || '|' ||
        NVL(r.pfc_guid, '<NULL>') || '|' ||
        NVL(r.payor_type_guid, '<NULL>') || '|' ||
        NVL(r.billing_form_code, '<NULL>') || '|' ||
        NVL(r.pfc_form_template_guid, '<NULL>') || '|' ||
        NVL(r.pfc_user_form_template_guid, '<NULL>') || '|' ||
        NVL(TO_CHAR(r.cpd_start_date, 'YYYYMMDDHH24MISS'), '<NULL>') || '|' ||
        NVL(TO_CHAR(r.cpd_end_date, 'YYYYMMDDHH24MISS'), '<NULL>')
            AS atom_text
    FROM params p
    CROSS JOIN pfc_resolution r
    UNION ALL
    SELECT
        1,
        d.target_order,
        d.target_segment,
        d.record_type_code,
        'TARGET|' || d.target_segment || '|' || d.record_type_code || '|' ||
        d.pfc_status || '|' || d.source_status || '|' ||
        NVL(d.source_electronic_rec_guid, '<NULL>') || '|' ||
        NVL(d.source_her_sto_proc_name, '<NULL>') || '|' ||
        NVL(d.desired_her_sto_proc_name, '<NULL>') || '|' ||
        'DESIRED_PAYOR_METADATA|<NULL>|Y|' ||
        d.source_equals_desired || '|' || d.target_action
    FROM target_decisions d
    UNION ALL
    SELECT
        2,
        h.target_order,
        h.target_segment,
        h.electronic_rec_guid,
        'SOURCE_HER|' || h.target_segment || '|' || h.electronic_rec_guid || '|' ||
        NVL(h.loop_id, '<NULL>') || '|' || NVL(h.contiguity_ind, '<NULL>') || '|' ||
        h.billing_form_code || '|' || h.record_name || '|' || h.record_type_code || '|' ||
        TO_CHAR(h.record_size, 'TM9') || '|' || NVL(h.mandatory_ind, '<NULL>') || '|' ||
        NVL(h.req_for_claim_ind, '<NULL>') || '|' || NVL(h.payor_type_guid, '<NULL>') || '|' ||
        NVL(h.payor_guid, '<NULL>') || '|' || NVL(h.plan_guid, '<NULL>') || '|' ||
        NVL(h.type_of_bill, '<NULL>') || '|' || NVL(h.detail_ind, '<NULL>') || '|' ||
        NVL(h.max_number, '<NULL>') || '|' || NVL(h.invoice_ind, '<NULL>') || '|' ||
        NVL(h.form_template_guid, '<NULL>') || '|' || NVL(h.carry_forward_ind, '<NULL>') || '|' ||
        NVL(TO_CHAR(h.max_carry_forward, 'TM9'), '<NULL>') || '|' ||
        NVL(h.sto_proc_name, '<NULL>') || '|' ||
        NVL(h.user_form_template_guid, '<NULL>') || '|' || NVL(h.notes, '<NULL>') || '|' ||
        NVL(h.include_record_data_onclaim, '<NULL>')
    FROM resolved_source_hers h
    UNION ALL
    SELECT
        3,
        f.target_order,
        f.target_segment,
        f.electronic_rec_guid || '|' || f.field_number,
        'SOURCE_HEF|' || f.target_segment || '|' || f.electronic_rec_guid || '|' ||
        RAWTOHEX(STANDARD_HASH(
            NVL(f.field_number, CHR(0)) || CHR(31) ||
            NVL(f.field_name, CHR(0)) || CHR(31) ||
            NVL(f.record_type_code, CHR(0)) || CHR(31) ||
            NVL(f.sto_proc_name, CHR(0)) || CHR(31) ||
            NVL(f.pic, CHR(0)) || CHR(31) || NVL(f.field_spec, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.position_from, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.position_thru, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(f.field_name_desc, CHR(0)) || CHR(31) ||
            NVL(f.mandatory_ind, CHR(0)) || CHR(31) ||
            NVL(f.must_fit_length_ind, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.order_num, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.repeats, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(f.detail_ind, CHR(0)) || CHR(31) || NVL(f.occurs_next, CHR(0)) || CHR(31) ||
            NVL(f.hard_coded_data, CHR(0)) || CHR(31) || NVL(f.field_format, CHR(0)) || CHR(31) ||
            NVL(f.caps_ind, CHR(0)) || CHR(31) || NVL(f.required_subelement_ind, CHR(0)) || CHR(31) ||
            NVL(f.include_data_onclaim, CHR(0)), 'SHA256'
        ))
    FROM source_hefs f
    UNION ALL
    SELECT
        4,
        d.target_order,
        d.target_segment,
        d.field_number || '|' || NVL(TO_CHAR(d.order_num, 'TM9'), '<NULL>'),
        'DESIRED_HEF|' || d.target_segment || '|' ||
        RAWTOHEX(STANDARD_HASH(
            NVL(d.field_number, CHR(0)) || CHR(31) || NVL(d.field_name, CHR(0)) || CHR(31) ||
            NVL(d.record_type_code, CHR(0)) || CHR(31) || NVL(d.sto_proc_name, CHR(0)) || CHR(31) ||
            NVL(d.pic, CHR(0)) || CHR(31) || NVL(d.field_spec, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.position_from, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.position_thru, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(d.field_name_desc, CHR(0)) || CHR(31) || NVL(d.mandatory_ind, CHR(0)) || CHR(31) ||
            NVL(d.must_fit_length_ind, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.order_num, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(d.repeats, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(d.detail_ind, CHR(0)) || CHR(31) || NVL(d.occurs_next, CHR(0)) || CHR(31) ||
            NVL(d.hard_coded_data, CHR(0)) || CHR(31) || NVL(d.field_format, CHR(0)) || CHR(31) ||
            NVL(d.caps_ind, CHR(0)) || CHR(31) || NVL(d.required_subelement_ind, CHR(0)) || CHR(31) ||
            NVL(d.include_data_onclaim, CHR(0)), 'SHA256'
        ))
    FROM desired_hefs d
    UNION ALL
    SELECT
        5,
        h.target_order,
        h.target_segment,
        h.electronic_rec_guid,
        'CURRENT_HER|' || h.target_segment || '|' || h.electronic_rec_guid || '|' ||
        NVL(h.loop_id, '<NULL>') || '|' || NVL(h.contiguity_ind, '<NULL>') || '|' ||
        h.billing_form_code || '|' || h.record_name || '|' || h.record_type_code || '|' ||
        TO_CHAR(h.record_size, 'TM9') || '|' || NVL(h.mandatory_ind, '<NULL>') || '|' ||
        NVL(h.req_for_claim_ind, '<NULL>') || '|' || NVL(h.payor_type_guid, '<NULL>') || '|' ||
        NVL(h.payor_guid, '<NULL>') || '|' || NVL(h.plan_guid, '<NULL>') || '|' ||
        NVL(h.type_of_bill, '<NULL>') || '|' || NVL(h.detail_ind, '<NULL>') || '|' ||
        NVL(h.max_number, '<NULL>') || '|' || NVL(h.invoice_ind, '<NULL>') || '|' ||
        NVL(h.form_template_guid, '<NULL>') || '|' || NVL(h.carry_forward_ind, '<NULL>') || '|' ||
        NVL(TO_CHAR(h.max_carry_forward, 'TM9'), '<NULL>') || '|' ||
        NVL(h.sto_proc_name, '<NULL>') || '|' ||
        NVL(h.user_form_template_guid, '<NULL>') || '|' ||
        NVL(h.notes, '<NULL>') || '|' || NVL(h.include_record_data_onclaim, '<NULL>')
    FROM current_payor_hers h
    UNION ALL
    SELECT
        6,
        f.target_order,
        f.target_segment,
        f.electronic_rec_guid || '|' || f.field_number,
        'CURRENT_HEF|' || f.target_segment || '|' || f.electronic_rec_guid || '|' ||
        RAWTOHEX(STANDARD_HASH(
            NVL(f.field_number, CHR(0)) || CHR(31) || NVL(f.field_name, CHR(0)) || CHR(31) ||
            NVL(f.record_type_code, CHR(0)) || CHR(31) || NVL(f.sto_proc_name, CHR(0)) || CHR(31) ||
            NVL(f.pic, CHR(0)) || CHR(31) || NVL(f.field_spec, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.position_from, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.position_thru, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(f.field_name_desc, CHR(0)) || CHR(31) || NVL(f.mandatory_ind, CHR(0)) || CHR(31) ||
            NVL(f.must_fit_length_ind, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.order_num, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(f.repeats, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(f.detail_ind, CHR(0)) || CHR(31) || NVL(f.occurs_next, CHR(0)) || CHR(31) ||
            NVL(f.hard_coded_data, CHR(0)) || CHR(31) || NVL(f.field_format, CHR(0)) || CHR(31) ||
            NVL(f.caps_ind, CHR(0)) || CHR(31) || NVL(f.required_subelement_ind, CHR(0)) || CHR(31) ||
            NVL(f.include_data_onclaim, CHR(0)), 'SHA256'
        ))
    FROM current_payor_hefs f
),
state_atom_hashes AS (
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY atom_group, target_order, sort_value_1, sort_value_2,
                     atom_text
        ) AS atom_number,
        RAWTOHEX(STANDARD_HASH(atom_text, 'SHA256')) AS atom_hash
    FROM state_atoms_raw
),
state_hash_buckets AS (
    SELECT
        TRUNC((atom_number - 1) / 40) AS bucket_number,
        RAWTOHEX(STANDARD_HASH(
            LISTAGG(atom_hash, '') WITHIN GROUP (ORDER BY atom_number),
            'SHA256'
        )) AS bucket_hash
    FROM state_atom_hashes
    GROUP BY TRUNC((atom_number - 1) / 40)
),
state_hash_size AS (
    SELECT COUNT(*) AS bucket_count
    FROM state_hash_buckets
),
state_hash_value AS (
    SELECT RAWTOHEX(STANDARD_HASH(
        LISTAGG(bucket_hash, '') WITHIN GROUP (ORDER BY bucket_number),
        'SHA256'
    )) AS preview_state_hash
    FROM state_hash_buckets
    WHERE bucket_number < 60
),
state_hash_result AS (
    SELECT
        CASE WHEN s.bucket_count <= 60 THEN v.preview_state_hash END
            AS preview_state_hash,
        CASE WHEN s.bucket_count <= 60 THEN 'CALCULATED'
             ELSE 'BLOCKED_STATE_TOO_LARGE' END AS state_hash_status
    FROM state_hash_size s
    CROSS JOIN state_hash_value v
)
SELECT
    d.target_segment,
    d.record_type_code,
    d.input_status,
    d.option_code,
    d.pfc_status,
    d.pfc_guid,
    d.pfc_plan_guid,
    d.payor_type_guid,
    d.billing_form_code,
    d.source_status,
    d.source_electronic_rec_guid,
    d.source_form_template_guid,
    d.source_user_form_template_guid,
    d.source_equals_desired,
    d.existing_payor_her_count,
    d.existing_payor_hef_count,
    d.current_matches_desired,
    d.current_her_electronic_rec_guid,
    d.her_attribute_mismatch_detail,
    d.source_her_loop_id,
    d.current_her_loop_id,
    d.source_her_loop_id AS desired_her_loop_id,
    d.source_her_contiguity_ind,
    d.current_her_contiguity_ind,
    d.source_her_contiguity_ind AS desired_her_contiguity_ind,
    d.source_her_billing_form_code,
    d.current_her_billing_form_code,
    d.source_her_billing_form_code AS desired_her_billing_form_code,
    d.source_her_record_name,
    d.current_her_record_name,
    d.source_her_record_name AS desired_her_record_name,
    d.source_her_record_type_code,
    d.current_her_record_type_code,
    d.source_her_record_type_code AS desired_her_record_type_code,
    d.source_her_record_size,
    d.current_her_record_size,
    d.source_her_record_size AS desired_her_record_size,
    d.source_her_mandatory_ind,
    d.current_her_mandatory_ind,
    d.source_her_mandatory_ind AS desired_her_mandatory_ind,
    d.source_her_req_for_claim_ind,
    d.current_her_req_for_claim_ind,
    d.source_her_req_for_claim_ind AS desired_her_req_for_claim_ind,
    d.source_her_payor_type_guid,
    d.current_her_payor_type_guid,
    d.desired_her_payor_type_guid,
    d.source_her_payor_guid,
    d.current_her_payor_guid,
    d.desired_her_payor_guid,
    d.source_her_plan_guid,
    d.current_her_plan_guid,
    d.desired_her_plan_guid,
    d.source_her_type_of_bill,
    d.current_her_type_of_bill,
    d.desired_her_type_of_bill,
    d.source_her_detail_ind,
    d.current_her_detail_ind,
    d.source_her_detail_ind AS desired_her_detail_ind,
    d.source_her_max_number,
    d.current_her_max_number,
    d.source_her_max_number AS desired_her_max_number,
    d.source_her_invoice_ind,
    d.current_her_invoice_ind,
    d.source_her_invoice_ind AS desired_her_invoice_ind,
    d.source_her_form_template_guid,
    d.current_her_form_template_guid,
    d.desired_her_form_template_guid,
    d.source_her_carry_forward_ind,
    d.current_her_carry_forward_ind,
    d.desired_her_carry_forward_ind,
    d.source_her_max_carry_forward,
    d.current_her_max_carry_forward,
    d.source_her_max_carry_forward AS desired_her_max_carry_forward,
    d.source_her_sto_proc_name,
    d.current_her_sto_proc_name,
    d.desired_her_sto_proc_name,
    d.source_her_user_form_template_guid,
    d.current_her_user_form_template_guid,
    d.desired_her_user_form_template_guid,
    d.source_her_notes,
    d.current_her_notes,
    d.source_her_notes AS desired_her_notes,
    d.source_her_include_onclaim,
    d.current_her_include_onclaim,
    d.desired_her_include_onclaim,
    CASE WHEN d.source_equals_desired = 'Y' THEN 0
         ELSE d.missing_hef_count END AS missing_hef_count,
    CASE WHEN d.source_equals_desired = 'Y' THEN 0
         ELSE d.duplicate_hef_count END AS duplicate_hef_count,
    CASE WHEN d.source_equals_desired = 'Y' THEN 0
         ELSE d.extra_hef_count END AS extra_hef_count,
    d.her_sto_mismatch_count,
    d.her_payor_type_mismatch_count,
    d.hef_sto_mismatch_count,
    d.hef_hard_mismatch_count,
    d.hef_cloned_attribute_mismatch_count,
    d.target_action,
    d.diagnostic_reason,
    CASE WHEN h.state_hash_status <> 'CALCULATED' THEN 'BLOCKED'
         ELSE o.overall_action END AS overall_action,
    CASE WHEN h.state_hash_status <> 'CALCULATED' THEN 'BLOCKED'
         ELSE o.overall_status END AS overall_status,
    h.preview_state_hash,
    h.state_hash_status
FROM target_decisions d
CROSS JOIN overall_result o
CROSS JOIN state_hash_result h
ORDER BY d.target_order;
