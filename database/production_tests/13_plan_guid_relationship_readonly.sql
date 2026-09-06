/*
 * PRODUCTION HARNESS CLASS: READ_ONLY
 * STANDALONE: YES
 * TOOL-OWNED OBJECT DEPENDENCIES: NONE
 *
 * Investigate how eligible plan/no-plan PFC rows relate to every payor-owned
 * 837I HER. Edit only MANUAL_INPUTS below. NULL PAYOR_GUID discovers payors;
 * a populated PAYOR_GUID returns full detail for that payor.
 *
 * This report gathers evidence only. It does not implement Payor Copy or a
 * PLAN_GUID rule in the configuration engine.
 *
 * Future Payor Copy decisions documented for context:
 * - A payor with no eligible PFC cannot be selected, one eligible PFC can be
 *   selected automatically, and multiple eligible PFCs require an explicit
 *   plan/no-plan PFC choice. Never guess between PFC contexts.
 * - Evidence is needed to decide whether copied HER.PLAN_GUID should equal a
 *   selected plan PFC and remain NULL for a selected no-plan PFC.
 * - Copy scope will include all template-valid payor HERs and their complete
 *   HEF children, not only record types currently recognized by the tool.
 * - Template-less HERs are valid for templated PFCs. Stale populated template
 *   associations will be ignored by the future copy operation.
 * - The future operation is destructive replacement of destination payor HERs.
 *   Its optional template-copy choice will determine associations against the
 *   resulting destination PFC; source HER template GUIDs must not be copied
 *   blindly. None of that behavior is performed by this script.
 */
SET DEFINE OFF

WITH
manual_inputs AS (
    /* MANUAL INPUTS: leave NULL for discovery mode. */
    SELECT CAST(NULL AS VARCHAR2(36)) AS payor_guid
    FROM dual
),
params AS (
    SELECT TRIM(payor_guid) AS payor_guid
    FROM manual_inputs
),
eligible_pfcs AS (
    SELECT
        p.payor_guid,
        p.pfc_guid,
        p.plan_guid,
        p.billing_form_code,
        p.form_template_guid,
        p.user_form_template_guid,
        p.cpd_start_date,
        p.cpd_end_date,
        p.default_media_type
    FROM pfc p
    CROSS JOIN params x
    WHERE p.payor_guid IS NOT NULL
      AND (x.payor_guid IS NULL OR p.payor_guid = x.payor_guid)
      AND p.cpd_end_date > SYSDATE
      AND p.type_of_bill IS NULL
      AND p.billing_form_code = '837I_5010'
      AND p.default_media_type = 'E'
      AND (
          p.user_form_template_guid IS NULL
          OR p.user_form_template_guid NOT IN (
              'E7BFA6270CF163DEE030007F010072AC',
              '9C3D46EEE7DB42B8AAE82B7A1038E223',
              '901B7182232A47EDAD5AB6B02F90F84C',
              'D9E9C52782F54AA29B27A058FCB6F412'
          )
      )
),
eligible_payors AS (
    SELECT DISTINCT payor_guid
    FROM eligible_pfcs
),
pfc_payor_stats AS (
    SELECT
        payor_guid,
        COUNT(*) AS eligible_pfc_count,
        SUM(CASE WHEN plan_guid IS NULL THEN 1 ELSE 0 END)
            AS no_plan_pfc_count,
        SUM(CASE WHEN plan_guid IS NOT NULL THEN 1 ELSE 0 END)
            AS plan_pfc_count,
        COUNT(DISTINCT plan_guid) AS distinct_plan_guid_count,
        COUNT(DISTINCT NVL(form_template_guid, '<NULL>'))
            AS distinct_form_template_count,
        COUNT(DISTINCT NVL(user_form_template_guid, '<NULL>'))
            AS distinct_user_template_count
    FROM eligible_pfcs
    GROUP BY payor_guid
),
payor_hers AS (
    SELECT h.*
    FROM hcfa_electronic_records h
    JOIN eligible_payors p ON p.payor_guid = h.payor_guid
    WHERE h.payor_guid IS NOT NULL
      AND h.billing_form_code = '837I_5010'
),
payor_her_stats AS (
    SELECT
        p.payor_guid,
        COUNT(h.electronic_rec_guid) AS payor_her_count,
        COUNT(CASE WHEN h.plan_guid IS NOT NULL
                   THEN h.electronic_rec_guid END)
            AS her_with_plan_guid_count,
        COUNT(CASE WHEN h.plan_guid IS NULL
                   THEN h.electronic_rec_guid END)
            AS her_with_null_plan_guid_count,
        COUNT(CASE WHEN h.type_of_bill IS NOT NULL
                   THEN h.electronic_rec_guid END)
            AS her_with_type_of_bill_count
    FROM eligible_payors p
    LEFT JOIN payor_hers h ON h.payor_guid = p.payor_guid
    GROUP BY p.payor_guid
),
/*
 * This compact pairing carries identifiers and classifications only. It is
 * aggregated immediately and avoids retaining full PFC/HER detail for every
 * production payor. Full detail is rebuilt later only for selected payors.
 */
compact_context_pairs AS (
    SELECT
        h.payor_guid,
        h.electronic_rec_guid,
        p.pfc_guid,
        CASE
            WHEN h.user_form_template_guid IS NOT NULL
             AND h.user_form_template_guid = p.user_form_template_guid
             AND (h.form_template_guid = p.form_template_guid
                  OR h.form_template_guid IS NULL)
                THEN 'USER_TEMPLATE_VALID'
            WHEN h.user_form_template_guid IS NULL
             AND h.form_template_guid IS NOT NULL
             AND h.form_template_guid = p.form_template_guid
                THEN 'FORM_TEMPLATE_VALID'
            WHEN h.user_form_template_guid IS NULL
             AND h.form_template_guid IS NULL
                THEN 'BILLING_FORM_VALID'
            ELSE 'STALE_TEMPLATE_ASSOCIATION'
        END AS template_context_status,
        CASE
            WHEN DECODE(p.plan_guid, h.plan_guid, 1, 0) = 1
                THEN 'EXACT_PLAN_MATCH'
            WHEN p.plan_guid IS NOT NULL AND h.plan_guid IS NULL
                THEN 'HER_PLAN_NULL_FOR_PLAN_PFC'
            WHEN p.plan_guid IS NOT NULL AND h.plan_guid IS NOT NULL
                THEN 'HER_PLAN_DIFFERENT'
            ELSE 'HER_PLAN_POPULATED_FOR_NO_PLAN_PFC'
        END AS plan_context_status,
        CASE WHEN p.plan_guid IS NOT NULL THEN 1 ELSE 0 END
            AS plan_specific_pfc_ind
    FROM payor_hers h
    JOIN eligible_pfcs p
      ON p.payor_guid = h.payor_guid
     AND p.billing_form_code = h.billing_form_code
),
her_context_counts AS (
    SELECT
        payor_guid,
        electronic_rec_guid,
        SUM(CASE WHEN template_context_status <>
                          'STALE_TEMPLATE_ASSOCIATION'
                 THEN 1 ELSE 0 END) AS eligible_pfc_match_count,
        SUM(CASE WHEN template_context_status <>
                          'STALE_TEMPLATE_ASSOCIATION'
                  AND plan_context_status = 'EXACT_PLAN_MATCH'
                 THEN 1 ELSE 0 END) AS exact_plan_pfc_match_count,
        SUM(CASE WHEN template_context_status <>
                          'STALE_TEMPLATE_ASSOCIATION'
                  AND plan_context_status = 'HER_PLAN_NULL_FOR_PLAN_PFC'
                 THEN 1 ELSE 0 END) AS plan_null_pfc_context_count,
        SUM(CASE WHEN template_context_status <>
                          'STALE_TEMPLATE_ASSOCIATION'
                  AND plan_context_status = 'HER_PLAN_DIFFERENT'
                 THEN 1 ELSE 0 END) AS different_plan_pfc_context_count,
        SUM(CASE WHEN template_context_status <>
                          'STALE_TEMPLATE_ASSOCIATION'
                  AND plan_context_status =
                          'HER_PLAN_POPULATED_FOR_NO_PLAN_PFC'
                 THEN 1 ELSE 0 END) AS populated_no_plan_pfc_context_count,
        SUM(CASE WHEN template_context_status <>
                          'STALE_TEMPLATE_ASSOCIATION'
                  AND plan_specific_pfc_ind = 1
                 THEN 1 ELSE 0 END) AS plan_specific_pfc_context_count
    FROM compact_context_pairs
    GROUP BY payor_guid, electronic_rec_guid
),
context_payor_stats AS (
    SELECT
        payor_guid,
        COUNT(CASE WHEN eligible_pfc_match_count > 0 THEN 1 END)
            AS valid_template_her_count,
        COUNT(CASE WHEN eligible_pfc_match_count = 0 THEN 1 END)
            AS stale_template_her_count,
        COUNT(CASE WHEN exact_plan_pfc_match_count > 0 THEN 1 END)
            AS valid_her_exact_plan_count,
        COUNT(CASE WHEN plan_null_pfc_context_count > 0 THEN 1 END)
            AS valid_her_null_plan_on_plan_pfc_count,
        COUNT(CASE WHEN different_plan_pfc_context_count > 0 THEN 1 END)
            AS valid_her_different_plan_count,
        COUNT(CASE WHEN populated_no_plan_pfc_context_count > 0 THEN 1 END)
            AS valid_her_populated_plan_on_no_plan_count,
        COUNT(CASE WHEN eligible_pfc_match_count > 1 THEN 1 END)
            AS her_matching_multiple_pfcs_count,
        COUNT(CASE WHEN eligible_pfc_match_count = 0 THEN 1 END)
            AS her_with_no_valid_pfc_count,
        COUNT(CASE WHEN plan_specific_pfc_context_count > 0 THEN 1 END)
            AS her_with_plan_pfc_context_count
    FROM her_context_counts
    GROUP BY payor_guid
),
discovery_base AS (
    SELECT
        p.payor_guid,
        p.eligible_pfc_count,
        p.no_plan_pfc_count,
        p.plan_pfc_count,
        p.distinct_plan_guid_count,
        p.distinct_form_template_count,
        p.distinct_user_template_count,
        h.payor_her_count,
        h.her_with_plan_guid_count,
        h.her_with_null_plan_guid_count,
        h.her_with_type_of_bill_count,
        NVL(c.valid_template_her_count, 0) AS valid_template_her_count,
        NVL(c.stale_template_her_count, 0) AS stale_template_her_count,
        NVL(c.valid_her_exact_plan_count, 0)
            AS valid_her_exact_plan_count,
        NVL(c.valid_her_null_plan_on_plan_pfc_count, 0)
            AS valid_her_null_plan_on_plan_pfc_count,
        NVL(c.valid_her_different_plan_count, 0)
            AS valid_her_different_plan_count,
        NVL(c.valid_her_populated_plan_on_no_plan_count, 0)
            AS valid_her_populated_plan_on_no_plan_count,
        NVL(c.her_matching_multiple_pfcs_count, 0)
            AS her_matching_multiple_pfcs_count,
        NVL(c.her_with_no_valid_pfc_count, 0)
            AS her_with_no_valid_pfc_count,
        NVL(c.her_with_plan_pfc_context_count, 0)
            AS her_with_plan_pfc_context_count
    FROM pfc_payor_stats p
    JOIN payor_her_stats h ON h.payor_guid = p.payor_guid
    LEFT JOIN context_payor_stats c ON c.payor_guid = p.payor_guid
),
discovery_labeled AS (
    SELECT
        d.*,
        CASE
            WHEN d.eligible_pfc_count > 1
             AND (d.distinct_plan_guid_count > 1
                  OR (d.plan_pfc_count > 0 AND d.no_plan_pfc_count > 0))
             AND d.payor_her_count > 0
             AND d.valid_her_exact_plan_count > 0
             AND (d.valid_her_null_plan_on_plan_pfc_count > 0
                  OR d.valid_her_different_plan_count > 0
                  OR d.valid_her_populated_plan_on_no_plan_count > 0)
                THEN 'HIGH_VALUE_MULTI_PLAN_MIXED'
            WHEN d.plan_pfc_count > 1
             AND d.valid_her_exact_plan_count > 0
             AND d.valid_her_null_plan_on_plan_pfc_count = 0
             AND d.valid_her_different_plan_count = 0
             AND d.valid_her_populated_plan_on_no_plan_count = 0
                THEN 'HIGH_VALUE_MULTI_PLAN_EXACT'
            WHEN d.plan_pfc_count > 1
             AND d.payor_her_count > 0
             AND d.her_with_plan_guid_count = 0
                THEN 'HIGH_VALUE_MULTI_PLAN_ALL_HER_NULL'
            WHEN d.plan_pfc_count > 0
             AND d.valid_her_exact_plan_count > 0
             AND d.valid_her_null_plan_on_plan_pfc_count = 0
             AND d.valid_her_different_plan_count = 0
                THEN 'PLAN_PFC_WITH_EXACT_HERS'
            WHEN d.plan_pfc_count > 0
             AND d.valid_her_null_plan_on_plan_pfc_count > 0
             AND d.valid_her_exact_plan_count = 0
                THEN 'PLAN_PFC_WITH_NULL_HERS'
            WHEN d.valid_her_exact_plan_count > 0
             AND (d.valid_her_null_plan_on_plan_pfc_count > 0
                  OR d.valid_her_different_plan_count > 0
                  OR d.valid_her_populated_plan_on_no_plan_count > 0)
                THEN 'MIXED_PLAN_BEHAVIOR'
            WHEN d.payor_her_count = 0 THEN 'NO_PAYOR_HERS'
            WHEN d.stale_template_her_count > d.valid_template_her_count
                THEN 'STALE_HEAVY'
            ELSE 'OTHER'
        END AS discovery_classification
    FROM discovery_base d
),
discovery_scored AS (
    SELECT
        d.*,
        CASE d.discovery_classification
            WHEN 'HIGH_VALUE_MULTI_PLAN_MIXED' THEN 1
            WHEN 'HIGH_VALUE_MULTI_PLAN_EXACT' THEN 2
            WHEN 'HIGH_VALUE_MULTI_PLAN_ALL_HER_NULL' THEN 3
            WHEN 'PLAN_PFC_WITH_EXACT_HERS' THEN 4
            WHEN 'PLAN_PFC_WITH_NULL_HERS' THEN 5
            WHEN 'MIXED_PLAN_BEHAVIOR' THEN 6
            WHEN 'STALE_HEAVY' THEN 7
            WHEN 'NO_PAYOR_HERS' THEN 8
            ELSE 9
        END AS discovery_priority,
        ROUND(100 * d.valid_her_exact_plan_count /
            NULLIF(d.valid_template_her_count, 0), 2)
            AS percent_valid_hers_with_exact_plan,
        ROUND(100 * d.valid_her_null_plan_on_plan_pfc_count /
            NULLIF(d.her_with_plan_pfc_context_count, 0), 2)
            AS percent_plan_pfc_hers_with_null_plan
    FROM discovery_labeled d
),
discovery_ranked AS (
    SELECT
        d.*,
        ROW_NUMBER() OVER (
            ORDER BY d.discovery_priority,
                     d.eligible_pfc_count DESC,
                     d.payor_her_count DESC,
                     d.payor_guid
        ) AS detail_rank
    FROM discovery_scored d
),
selected_payors AS (
    SELECT d.payor_guid
    FROM discovery_ranked d
    CROSS JOIN params x
    WHERE (x.payor_guid IS NULL AND d.detail_rank <= 25)
       OR (x.payor_guid IS NOT NULL AND d.payor_guid = x.payor_guid)
),
selected_pfcs AS (
    SELECT p.*
    FROM eligible_pfcs p
    JOIN selected_payors s ON s.payor_guid = p.payor_guid
),
selected_hers AS (
    SELECT h.*
    FROM payor_hers h
    JOIN selected_payors s ON s.payor_guid = h.payor_guid
),
hef_counts AS (
    SELECT
        h.electronic_rec_guid,
        COUNT(f.electronic_rec_guid) AS hef_count
    FROM selected_hers h
    LEFT JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
    GROUP BY h.electronic_rec_guid
),
detail_pair_base AS (
    SELECT
        p.payor_guid,
        p.pfc_guid,
        p.plan_guid AS pfc_plan_guid,
        p.billing_form_code AS pfc_billing_form_code,
        p.form_template_guid AS pfc_form_template_guid,
        p.user_form_template_guid AS pfc_user_form_template_guid,
        p.cpd_start_date,
        p.cpd_end_date,
        p.default_media_type,
        h.electronic_rec_guid AS her_electronic_rec_guid,
        h.record_type_code AS her_record_type_code,
        h.record_name AS her_record_name,
        h.loop_id AS her_loop_id,
        h.plan_guid AS her_plan_guid,
        h.form_template_guid AS her_form_template_guid,
        h.user_form_template_guid AS her_user_form_template_guid,
        h.sto_proc_name AS her_sto_proc_name,
        h.mandatory_ind AS her_mandatory_ind,
        h.type_of_bill AS her_type_of_bill,
        h.rec_ent_date AS her_rec_ent_date,
        h.rec_ent_user AS her_rec_ent_user,
        h.rec_mod_date AS her_rec_mod_date,
        h.rec_mod_user AS her_rec_mod_user,
        f.hef_count,
        CASE
            WHEN h.user_form_template_guid IS NOT NULL
             AND h.user_form_template_guid = p.user_form_template_guid
             AND (h.form_template_guid = p.form_template_guid
                  OR h.form_template_guid IS NULL)
                THEN 'USER_TEMPLATE_VALID'
            WHEN h.user_form_template_guid IS NULL
             AND h.form_template_guid IS NOT NULL
             AND h.form_template_guid = p.form_template_guid
                THEN 'FORM_TEMPLATE_VALID'
            WHEN h.user_form_template_guid IS NULL
             AND h.form_template_guid IS NULL
                THEN 'BILLING_FORM_VALID'
            ELSE 'STALE_TEMPLATE_ASSOCIATION'
        END AS template_context_status,
        CASE
            WHEN DECODE(p.plan_guid, h.plan_guid, 1, 0) = 1
                THEN 'EXACT_PLAN_MATCH'
            WHEN p.plan_guid IS NOT NULL AND h.plan_guid IS NULL
                THEN 'HER_PLAN_NULL_FOR_PLAN_PFC'
            WHEN p.plan_guid IS NOT NULL AND h.plan_guid IS NOT NULL
                THEN 'HER_PLAN_DIFFERENT'
            ELSE 'HER_PLAN_POPULATED_FOR_NO_PLAN_PFC'
        END AS plan_context_status
    FROM selected_pfcs p
    JOIN selected_hers h
      ON h.payor_guid = p.payor_guid
     AND h.billing_form_code = p.billing_form_code
    JOIN hef_counts f
      ON f.electronic_rec_guid = h.electronic_rec_guid
),
detail_pairs AS (
    SELECT
        d.*,
        CASE
            WHEN d.her_type_of_bill IS NOT NULL
                THEN 'HER_TYPE_OF_BILL_PRESENT'
            WHEN d.template_context_status = 'STALE_TEMPLATE_ASSOCIATION'
                THEN 'INVALID_TEMPLATE_CONTEXT'
            WHEN d.plan_context_status = 'EXACT_PLAN_MATCH'
                THEN 'VALID_EXACT_PLAN'
            WHEN d.plan_context_status = 'HER_PLAN_NULL_FOR_PLAN_PFC'
                THEN 'VALID_BUT_HER_PLAN_NULL'
            WHEN d.plan_context_status = 'HER_PLAN_DIFFERENT'
                THEN 'INVALID_PLAN_MISMATCH'
            ELSE 'INVALID_PLAN_FOR_NO_PLAN_PFC'
        END AS ownership_status
    FROM detail_pair_base d
),
pfc_summaries AS (
    SELECT
        p.payor_guid,
        p.pfc_guid,
        p.plan_guid,
        p.billing_form_code,
        p.form_template_guid,
        p.user_form_template_guid,
        p.cpd_start_date,
        p.cpd_end_date,
        p.default_media_type,
        COUNT(CASE WHEN d.template_context_status <>
                            'STALE_TEMPLATE_ASSOCIATION'
                   THEN d.her_electronic_rec_guid END)
            AS template_valid_her_count,
        COUNT(CASE WHEN d.template_context_status <>
                            'STALE_TEMPLATE_ASSOCIATION'
                    AND d.plan_context_status = 'EXACT_PLAN_MATCH'
                   THEN d.her_electronic_rec_guid END)
            AS exact_plan_her_count,
        COUNT(CASE WHEN d.template_context_status <>
                            'STALE_TEMPLATE_ASSOCIATION'
                    AND d.her_plan_guid IS NULL
                   THEN d.her_electronic_rec_guid END)
            AS null_plan_her_count,
        COUNT(CASE WHEN d.template_context_status <>
                            'STALE_TEMPLATE_ASSOCIATION'
                    AND d.plan_context_status = 'HER_PLAN_DIFFERENT'
                   THEN d.her_electronic_rec_guid END)
            AS different_plan_her_count,
        COUNT(CASE WHEN d.template_context_status <>
                            'STALE_TEMPLATE_ASSOCIATION'
                    AND d.plan_context_status =
                            'HER_PLAN_POPULATED_FOR_NO_PLAN_PFC'
                   THEN d.her_electronic_rec_guid END)
            AS populated_plan_for_no_plan_her_count,
        COUNT(CASE WHEN d.template_context_status =
                            'STALE_TEMPLATE_ASSOCIATION'
                   THEN d.her_electronic_rec_guid END)
            AS stale_template_her_count,
        s.eligible_pfc_count - 1 AS other_pfc_count_for_payor,
        s.plan_pfc_count - CASE WHEN p.plan_guid IS NOT NULL THEN 1 ELSE 0 END
            AS other_plan_pfc_count_for_payor
    FROM selected_pfcs p
    JOIN discovery_ranked s ON s.payor_guid = p.payor_guid
    LEFT JOIN detail_pairs d ON d.pfc_guid = p.pfc_guid
    GROUP BY
        p.payor_guid, p.pfc_guid, p.plan_guid, p.billing_form_code,
        p.form_template_guid, p.user_form_template_guid,
        p.cpd_start_date, p.cpd_end_date, p.default_media_type,
        s.eligible_pfc_count, s.plan_pfc_count
)
SELECT *
FROM (
SELECT
    'PAYOR_DISCOVERY' AS output_section,
    1 AS output_order,
    d.discovery_priority,
    d.discovery_classification,
    d.payor_guid,
    d.eligible_pfc_count,
    d.no_plan_pfc_count,
    d.plan_pfc_count,
    d.distinct_plan_guid_count,
    d.distinct_form_template_count,
    d.distinct_user_template_count,
    d.payor_her_count,
    d.her_with_plan_guid_count,
    d.her_with_null_plan_guid_count,
    d.her_with_type_of_bill_count,
    d.valid_template_her_count,
    d.stale_template_her_count,
    d.valid_her_exact_plan_count,
    d.valid_her_null_plan_on_plan_pfc_count,
    d.valid_her_different_plan_count,
    d.valid_her_populated_plan_on_no_plan_count,
    d.her_matching_multiple_pfcs_count,
    d.her_with_no_valid_pfc_count,
    d.percent_valid_hers_with_exact_plan,
    d.percent_plan_pfc_hers_with_null_plan,
    CAST(NULL AS VARCHAR2(36)) AS pfc_guid,
    CAST(NULL AS VARCHAR2(36)) AS pfc_plan_guid,
    CAST(NULL AS VARCHAR2(10)) AS pfc_billing_form_code,
    CAST(NULL AS VARCHAR2(36)) AS pfc_form_template_guid,
    CAST(NULL AS VARCHAR2(36)) AS pfc_user_form_template_guid,
    CAST(NULL AS DATE) AS cpd_start_date,
    CAST(NULL AS DATE) AS cpd_end_date,
    CAST(NULL AS VARCHAR2(2)) AS default_media_type,
    CAST(NULL AS NUMBER) AS template_valid_her_count,
    CAST(NULL AS NUMBER) AS exact_plan_her_count,
    CAST(NULL AS NUMBER) AS null_plan_her_count,
    CAST(NULL AS NUMBER) AS different_plan_her_count,
    CAST(NULL AS NUMBER) AS populated_plan_for_no_plan_her_count,
    CAST(NULL AS NUMBER) AS other_pfc_count_for_payor,
    CAST(NULL AS NUMBER) AS other_plan_pfc_count_for_payor,
    CAST(NULL AS VARCHAR2(36)) AS her_electronic_rec_guid,
    CAST(NULL AS VARCHAR2(20)) AS her_record_type_code,
    CAST(NULL AS VARCHAR2(50)) AS her_record_name,
    CAST(NULL AS VARCHAR2(20)) AS her_loop_id,
    CAST(NULL AS VARCHAR2(36)) AS her_plan_guid,
    CAST(NULL AS VARCHAR2(36)) AS her_form_template_guid,
    CAST(NULL AS VARCHAR2(36)) AS her_user_form_template_guid,
    CAST(NULL AS VARCHAR2(30)) AS her_sto_proc_name,
    CAST(NULL AS VARCHAR2(1)) AS her_mandatory_ind,
    CAST(NULL AS VARCHAR2(3)) AS her_type_of_bill,
    CAST(NULL AS DATE) AS her_rec_ent_date,
    CAST(NULL AS VARCHAR2(36)) AS her_rec_ent_user,
    CAST(NULL AS DATE) AS her_rec_mod_date,
    CAST(NULL AS VARCHAR2(36)) AS her_rec_mod_user,
    CAST(NULL AS NUMBER) AS hef_count,
    CAST(NULL AS VARCHAR2(30)) AS template_context_status,
    CAST(NULL AS VARCHAR2(40)) AS plan_context_status,
    CAST(NULL AS VARCHAR2(40)) AS ownership_status,
    CAST(NULL AS NUMBER) AS eligible_pfc_match_count,
    CAST(NULL AS NUMBER) AS exact_plan_pfc_match_count,
    CAST(NULL AS NUMBER) AS plan_null_pfc_context_count,
    CAST(NULL AS VARCHAR2(30)) AS pfc_context_classification
FROM discovery_ranked d
UNION ALL
SELECT
    'PFC_SUMMARY',
    2,
    CAST(NULL AS NUMBER),
    CAST(NULL AS VARCHAR2(40)),
    p.payor_guid,
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    p.stale_template_her_count,
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    p.pfc_guid,
    p.plan_guid,
    p.billing_form_code,
    p.form_template_guid,
    p.user_form_template_guid,
    p.cpd_start_date,
    p.cpd_end_date,
    p.default_media_type,
    p.template_valid_her_count,
    p.exact_plan_her_count,
    p.null_plan_her_count,
    p.different_plan_her_count,
    p.populated_plan_for_no_plan_her_count,
    p.other_pfc_count_for_payor,
    p.other_plan_pfc_count_for_payor,
    CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(20)),
    CAST(NULL AS VARCHAR2(50)), CAST(NULL AS VARCHAR2(20)),
    CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
    CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(30)),
    CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(3)),
    CAST(NULL AS DATE), CAST(NULL AS VARCHAR2(36)),
    CAST(NULL AS DATE), CAST(NULL AS VARCHAR2(36)),
    CAST(NULL AS NUMBER), CAST(NULL AS VARCHAR2(30)),
    CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(40)),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS VARCHAR2(30))
FROM pfc_summaries p
UNION ALL
SELECT
    'HER_DETAIL',
    3,
    CAST(NULL AS NUMBER),
    CAST(NULL AS VARCHAR2(40)),
    d.payor_guid,
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    d.pfc_guid,
    d.pfc_plan_guid,
    d.pfc_billing_form_code,
    d.pfc_form_template_guid,
    d.pfc_user_form_template_guid,
    d.cpd_start_date,
    d.cpd_end_date,
    d.default_media_type,
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
    CAST(NULL AS NUMBER),
    d.her_electronic_rec_guid,
    d.her_record_type_code,
    d.her_record_name,
    d.her_loop_id,
    d.her_plan_guid,
    d.her_form_template_guid,
    d.her_user_form_template_guid,
    d.her_sto_proc_name,
    d.her_mandatory_ind,
    d.her_type_of_bill,
    d.her_rec_ent_date,
    d.her_rec_ent_user,
    d.her_rec_mod_date,
    d.her_rec_mod_user,
    d.hef_count,
    d.template_context_status,
    d.plan_context_status,
    d.ownership_status,
    c.eligible_pfc_match_count,
    c.exact_plan_pfc_match_count,
    c.plan_null_pfc_context_count,
    CASE
        WHEN c.eligible_pfc_match_count = 0 THEN 'NO_VALID_PFC_CONTEXT'
        WHEN c.eligible_pfc_match_count = 1 THEN 'UNIQUE_PFC_CONTEXT'
        ELSE 'MULTIPLE_PFC_CONTEXTS'
    END
FROM detail_pairs d
JOIN her_context_counts c
  ON c.payor_guid = d.payor_guid
 AND c.electronic_rec_guid = d.her_electronic_rec_guid
) report_output
ORDER BY
    report_output.output_order,
    report_output.discovery_priority NULLS LAST,
    report_output.payor_guid,
    report_output.pfc_guid,
    report_output.her_record_type_code,
    report_output.her_electronic_rec_guid;
