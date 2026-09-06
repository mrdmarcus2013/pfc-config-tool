/*
 * PRODUCTION HARNESS CLASS: READ_ONLY
 * STANDALONE: YES
 * TOOL-OWNED OBJECT DEPENDENCIES: NONE
 *
 * Capture schema facts and aggregate configuration topology for durable PFC
 * Configuration Tool documentation and synthetic-fixture design. This script
 * does not implement Payor Copy or change configuration behavior.
 *
 * Run in Toad as a script. It returns three independent result grids:
 *   1. SCHEMA_COLUMNS
 *   2. SCHEMA_RELATIONSHIPS
 *   3. structural sections 3 through 10
 *
 * The first two statements use standard ALL_* dictionary views. They require
 * only metadata already visible to the connected account. If those views are
 * restricted on a server, do not request elevated privileges: run the third
 * statement independently and report that metadata capture was unavailable.
 *
 * Privacy: no payor names, descriptive customer data, notes, HEF values, or
 * audit-user values are selected. GUIDs appear only in the bounded
 * REPRESENTATIVE_CONTEXTS section, where relational examples require them.
 */
SET DEFINE OFF

/* ================================================================
 * 1. SCHEMA_COLUMNS
 * DATA_DEFAULT is selected directly because Oracle exposes it as LONG on
 * older versions; keeping this out of a UNION avoids LONG conversion errors.
 * ================================================================ */
SELECT
    'SCHEMA_COLUMNS' AS output_section,
    1 AS output_order,
    c.owner AS owner_name,
    c.table_name,
    c.column_id,
    c.column_name,
    c.data_type,
    c.data_length,
    c.data_precision,
    c.data_scale,
    c.nullable,
    c.data_default
FROM all_tab_columns c
WHERE c.table_name IN (
    'PAYORS',
    'PFC',
    'HCFA_ELECTRONIC_RECORDS',
    'HCFA_ELECTRONIC_FIELDS'
)
ORDER BY c.owner, c.table_name, c.column_id;

/* ================================================================
 * 2. SCHEMA_RELATIONSHIPS
 * LOGICAL_RELATIONSHIP_CHECK rows say explicitly whether an expected logical
 * relationship has a declared visible foreign key. Remaining rows inventory
 * the visible constraints and indexes without inventing relationships.
 * ================================================================ */
WITH
target_constraints AS (
    SELECT c.*
    FROM all_constraints c
    WHERE c.table_name IN (
        'PAYORS', 'PFC',
        'HCFA_ELECTRONIC_RECORDS', 'HCFA_ELECTRONIC_FIELDS'
    )
),
constraint_details AS (
    SELECT
        c.owner AS owner_name,
        c.table_name AS child_table,
        cc.position AS column_position,
        cc.column_name AS child_column,
        c.constraint_name,
        c.constraint_type,
        c.r_owner AS referenced_owner,
        c.r_constraint_name AS referenced_constraint_name,
        parent.table_name AS parent_table,
        parent_col.column_name AS parent_column
    FROM target_constraints c
    LEFT JOIN all_cons_columns cc
      ON cc.owner = c.owner
     AND cc.constraint_name = c.constraint_name
     AND cc.table_name = c.table_name
    LEFT JOIN all_constraints parent
      ON parent.owner = c.r_owner
     AND parent.constraint_name = c.r_constraint_name
    LEFT JOIN all_cons_columns parent_col
      ON parent_col.owner = parent.owner
     AND parent_col.constraint_name = parent.constraint_name
     AND parent_col.table_name = parent.table_name
     AND parent_col.position = cc.position
),
actual_foreign_keys AS (
    SELECT *
    FROM constraint_details
    WHERE constraint_type = 'R'
),
expected_relationships AS (
    SELECT 'PFC_PAYOR' AS relationship_name,
           'PFC' AS child_table, 'PAYOR_GUID' AS child_column,
           'PAYORS' AS parent_table, 'PAYOR_GUID' AS parent_column
    FROM dual
    UNION ALL
    SELECT 'HER_PAYOR', 'HCFA_ELECTRONIC_RECORDS', 'PAYOR_GUID',
           'PAYORS', 'PAYOR_GUID' FROM dual
    UNION ALL
    SELECT 'HEF_HER', 'HCFA_ELECTRONIC_FIELDS', 'ELECTRONIC_REC_GUID',
           'HCFA_ELECTRONIC_RECORDS', 'ELECTRONIC_REC_GUID' FROM dual
),
relationship_checks AS (
    SELECT
        e.relationship_name,
        e.child_table,
        e.child_column,
        e.parent_table,
        e.parent_column,
        MAX(f.owner_name) AS owner_name,
        MAX(f.constraint_name) AS constraint_name,
        COUNT(f.constraint_name) AS matching_fk_count
    FROM expected_relationships e
    LEFT JOIN actual_foreign_keys f
      ON f.child_table = e.child_table
     AND f.child_column = e.child_column
     AND f.parent_table = e.parent_table
     AND f.parent_column = e.parent_column
    GROUP BY
        e.relationship_name, e.child_table, e.child_column,
        e.parent_table, e.parent_column
),
index_details AS (
    SELECT
        i.table_owner AS owner_name,
        i.table_name,
        ic.column_position,
        ic.column_name,
        i.index_name,
        i.uniqueness
    FROM all_indexes i
    JOIN all_ind_columns ic
      ON ic.index_owner = i.owner
     AND ic.index_name = i.index_name
     AND ic.table_owner = i.table_owner
     AND ic.table_name = i.table_name
    WHERE i.table_name IN (
        'PAYORS', 'PFC',
        'HCFA_ELECTRONIC_RECORDS', 'HCFA_ELECTRONIC_FIELDS'
    )
)
SELECT *
FROM (
    SELECT
        'SCHEMA_RELATIONSHIPS' AS output_section,
        2 AS output_order,
        'LOGICAL_RELATIONSHIP_CHECK' AS metadata_kind,
        r.relationship_name,
        r.owner_name,
        r.parent_table,
        r.child_table,
        CAST(NULL AS NUMBER) AS column_position,
        r.child_column,
        r.parent_column,
        r.constraint_name,
        CAST('R' AS VARCHAR2(1)) AS constraint_type,
        CAST(NULL AS VARCHAR2(128)) AS referenced_owner,
        CAST(NULL AS VARCHAR2(128)) AS referenced_constraint_name,
        CAST(NULL AS VARCHAR2(128)) AS index_name,
        CAST(NULL AS VARCHAR2(9)) AS uniqueness,
        CASE WHEN r.matching_fk_count = 0
             THEN 'NO_DECLARED_FOREIGN_KEY_FOUND'
             ELSE 'DECLARED_FOREIGN_KEY_FOUND' END AS declaration_status
    FROM relationship_checks r
    UNION ALL
    SELECT
        'SCHEMA_RELATIONSHIPS', 2, 'CONSTRAINT',
        CAST(NULL AS VARCHAR2(40)),
        c.owner_name, c.parent_table, c.child_table, c.column_position,
        c.child_column, c.parent_column, c.constraint_name,
        c.constraint_type, c.referenced_owner,
        c.referenced_constraint_name,
        CAST(NULL AS VARCHAR2(128)), CAST(NULL AS VARCHAR2(9)),
        CAST(NULL AS VARCHAR2(40))
    FROM constraint_details c
    UNION ALL
    SELECT
        'SCHEMA_RELATIONSHIPS', 2, 'INDEX',
        CAST(NULL AS VARCHAR2(40)),
        i.owner_name, CAST(NULL AS VARCHAR2(128)), i.table_name,
        i.column_position, i.column_name, CAST(NULL AS VARCHAR2(128)),
        CAST(NULL AS VARCHAR2(128)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(128)), CAST(NULL AS VARCHAR2(128)),
        i.index_name, i.uniqueness, CAST(NULL AS VARCHAR2(40))
    FROM index_details i
) relationship_output
ORDER BY
    relationship_output.metadata_kind,
    relationship_output.owner_name,
    relationship_output.child_table,
    relationship_output.constraint_name,
    relationship_output.index_name,
    relationship_output.column_position;

/* ================================================================
 * 3-10. AGGREGATE CONFIGURATION REFERENCE CAPTURE
 * CPD_START_DATE is intentionally not an eligibility predicate.
 * ================================================================ */
WITH
eligible_pfcs AS (
    SELECT
        p.payor_guid,
        p.pfc_guid,
        p.plan_guid,
        p.billing_form_code,
        p.form_template_guid,
        p.user_form_template_guid,
        p.cpd_start_date,
        p.cpd_end_date
    FROM pfc p
    WHERE p.payor_guid IS NOT NULL
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
payor_hers AS (
    SELECT
        h.electronic_rec_guid,
        h.payor_guid,
        h.payor_type_guid,
        h.plan_guid,
        h.billing_form_code,
        h.record_type_code,
        h.type_of_bill,
        h.form_template_guid,
        h.user_form_template_guid
    FROM hcfa_electronic_records h
    WHERE h.payor_guid IS NOT NULL
      AND h.billing_form_code = '837I_5010'
),
hef_counts AS (
    SELECT
        h.electronic_rec_guid,
        COUNT(f.electronic_rec_guid) AS hef_count
    FROM payor_hers h
    LEFT JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
    GROUP BY h.electronic_rec_guid
),
her_with_hef AS (
    SELECT h.*, f.hef_count
    FROM payor_hers h
    JOIN hef_counts f ON f.electronic_rec_guid = h.electronic_rec_guid
),
pfc_payor_counts AS (
    SELECT
        payor_guid,
        COUNT(*) AS pfc_count,
        SUM(CASE WHEN plan_guid IS NULL THEN 1 ELSE 0 END)
            AS no_plan_pfc_count,
        SUM(CASE WHEN plan_guid IS NOT NULL THEN 1 ELSE 0 END)
            AS plan_pfc_count
    FROM eligible_pfcs
    GROUP BY payor_guid
),
duplicate_plan_payors AS (
    SELECT DISTINCT payor_guid
    FROM eligible_pfcs
    WHERE plan_guid IS NOT NULL
    GROUP BY payor_guid, plan_guid
    HAVING COUNT(*) > 1
),
pfc_topology_rows AS (
    SELECT 'EXACTLY_ONE_ELIGIBLE_PFC' AS pattern_category,
           COUNT(*) AS payor_count
    FROM pfc_payor_counts WHERE pfc_count = 1
    UNION ALL
    SELECT 'MULTIPLE_ELIGIBLE_PFCS', COUNT(*)
    FROM pfc_payor_counts WHERE pfc_count > 1
    UNION ALL
    SELECT 'ONLY_NO_PLAN_PFCS', COUNT(*)
    FROM pfc_payor_counts WHERE no_plan_pfc_count > 0 AND plan_pfc_count = 0
    UNION ALL
    SELECT 'ONLY_PLAN_SPECIFIC_PFCS', COUNT(*)
    FROM pfc_payor_counts WHERE no_plan_pfc_count = 0 AND plan_pfc_count > 0
    UNION ALL
    SELECT 'BOTH_NO_PLAN_AND_PLAN_PFCS', COUNT(*)
    FROM pfc_payor_counts WHERE no_plan_pfc_count > 0 AND plan_pfc_count > 0
    UNION ALL
    SELECT 'MULTIPLE_PFCS_SAME_POPULATED_PLAN', COUNT(*)
    FROM duplicate_plan_payors
),
context_base AS (
    SELECT
        p.payor_guid,
        p.pfc_guid,
        p.plan_guid AS pfc_plan_guid,
        p.billing_form_code,
        p.form_template_guid AS pfc_form_template_guid,
        p.user_form_template_guid AS pfc_user_form_template_guid,
        h.electronic_rec_guid,
        h.plan_guid AS her_plan_guid,
        h.record_type_code,
        h.form_template_guid AS her_form_template_guid,
        h.user_form_template_guid AS her_user_form_template_guid,
        h.type_of_bill AS her_type_of_bill,
        h.hef_count,
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
                THEN 'EXACT_PLAN'
            WHEN p.plan_guid IS NOT NULL AND h.plan_guid IS NULL
                THEN 'NULL_HER_FOR_PLAN_PFC'
            WHEN p.plan_guid IS NOT NULL AND h.plan_guid IS NOT NULL
                THEN 'OTHER_PLAN_HER'
            ELSE 'POPULATED_HER_FOR_NO_PLAN_PFC'
        END AS relationship_category,
        CASE
            WHEN h.user_form_template_guid IS NOT NULL THEN
                'USER|' || h.user_form_template_guid || '|FORM|' ||
                NVL(h.form_template_guid, '<NULL>')
            WHEN h.form_template_guid IS NOT NULL THEN
                'FORM|' || h.form_template_guid
            ELSE 'BILLING_FORM'
        END AS logical_template_context
    FROM eligible_pfcs p
    JOIN her_with_hef h
      ON h.payor_guid = p.payor_guid
     AND h.billing_form_code = p.billing_form_code
),
valid_contexts AS (
    SELECT *
    FROM context_base
    WHERE template_context_status <> 'STALE_TEMPLATE_ASSOCIATION'
),
pfc_context_presence AS (
    SELECT
        payor_guid,
        pfc_guid,
        pfc_plan_guid,
        SUM(CASE WHEN relationship_category = 'EXACT_PLAN'
                 THEN 1 ELSE 0 END) AS exact_count,
        SUM(CASE WHEN relationship_category = 'NULL_HER_FOR_PLAN_PFC'
                 THEN 1 ELSE 0 END) AS null_fallback_count,
        SUM(CASE WHEN relationship_category = 'OTHER_PLAN_HER'
                 THEN 1 ELSE 0 END) AS other_plan_count,
        SUM(CASE WHEN relationship_category =
                          'POPULATED_HER_FOR_NO_PLAN_PFC'
                 THEN 1 ELSE 0 END) AS populated_no_plan_count
    FROM valid_contexts
    GROUP BY payor_guid, pfc_guid, pfc_plan_guid
),
pfc_context_pattern_rows AS (
    SELECT 'PFC_CONTEXT_HAS_EXACT_PLAN_HERS' AS pattern_category,
           COUNT(*) AS pfc_count, COUNT(DISTINCT payor_guid) AS payor_count
    FROM pfc_context_presence WHERE exact_count > 0
    UNION ALL
    SELECT 'PFC_CONTEXT_HAS_NULL_FALLBACK_HERS',
           COUNT(*), COUNT(DISTINCT payor_guid)
    FROM pfc_context_presence
    WHERE pfc_plan_guid IS NOT NULL AND null_fallback_count > 0
    UNION ALL
    SELECT 'PFC_CONTEXT_HAS_EXACT_AND_NULL',
           COUNT(*), COUNT(DISTINCT payor_guid)
    FROM pfc_context_presence
    WHERE pfc_plan_guid IS NOT NULL
      AND exact_count > 0 AND null_fallback_count > 0
    UNION ALL
    SELECT 'PFC_CONTEXT_HAS_OTHER_PLAN_HERS',
           COUNT(*), COUNT(DISTINCT payor_guid)
    FROM pfc_context_presence WHERE other_plan_count > 0
    UNION ALL
    SELECT 'PLAN_PFC_CONTEXT_HAS_ONLY_NULL_HERS',
           COUNT(*), COUNT(DISTINCT payor_guid)
    FROM pfc_context_presence
    WHERE pfc_plan_guid IS NOT NULL
      AND null_fallback_count > 0
      AND exact_count = 0
      AND other_plan_count = 0
),
logical_identity_counts AS (
    SELECT
        payor_guid,
        pfc_guid,
        pfc_plan_guid,
        billing_form_code,
        record_type_code,
        template_context_status,
        logical_template_context,
        SUM(CASE WHEN relationship_category = 'EXACT_PLAN'
                 THEN 1 ELSE 0 END) AS exact_candidate_count,
        SUM(CASE WHEN relationship_category = 'NULL_HER_FOR_PLAN_PFC'
                 THEN 1 ELSE 0 END) AS null_candidate_count,
        SUM(CASE WHEN relationship_category = 'OTHER_PLAN_HER'
                 THEN 1 ELSE 0 END) AS other_candidate_count
    FROM valid_contexts
    WHERE pfc_plan_guid IS NOT NULL
    GROUP BY
        payor_guid, pfc_guid, pfc_plan_guid, billing_form_code,
        record_type_code, template_context_status, logical_template_context
),
logical_identity_classified AS (
    SELECT
        i.*,
        CASE
            WHEN exact_candidate_count > 0 AND null_candidate_count = 0
             AND other_candidate_count = 0 THEN 'A_EXACT_PLAN_ONLY'
            WHEN exact_candidate_count = 0 AND null_candidate_count > 0
             AND other_candidate_count = 0 THEN 'B_NULL_FALLBACK_ONLY'
            WHEN exact_candidate_count > 0 AND null_candidate_count > 0
             AND other_candidate_count = 0 THEN 'C_EXACT_AND_NULL'
            WHEN exact_candidate_count = 0 AND null_candidate_count = 0
             AND other_candidate_count > 0 THEN 'D_OTHER_PLAN_ONLY'
            WHEN exact_candidate_count > 0 AND null_candidate_count = 0
             AND other_candidate_count > 0 THEN 'E_EXACT_AND_OTHER'
            WHEN exact_candidate_count = 0 AND null_candidate_count > 0
             AND other_candidate_count > 0 THEN 'F_NULL_AND_OTHER'
            ELSE 'G_EXACT_NULL_AND_OTHER'
        END AS fallback_pattern
    FROM logical_identity_counts i
),
her_hef_populations AS (
    SELECT 'ALL_PAYOR_837I_HERS' AS pattern_category, h.*
    FROM her_with_hef h
    UNION ALL
    SELECT 'PLAN_POPULATED_PAYOR_HERS', h.*
    FROM her_with_hef h WHERE h.plan_guid IS NOT NULL
    UNION ALL
    SELECT 'NULL_PLAN_PAYOR_HERS', h.*
    FROM her_with_hef h WHERE h.plan_guid IS NULL
),
her_hef_bucketed AS (
    SELECT
        h.*,
        CASE
            WHEN hef_count = 0 THEN '0'
            WHEN hef_count = 1 THEN '1'
            WHEN hef_count BETWEEN 2 AND 5 THEN '2-5'
            WHEN hef_count BETWEEN 6 AND 20 THEN '6-20'
            ELSE '>20'
        END AS hef_count_bucket
    FROM her_hef_populations h
),
same_plan_pfc_counts AS (
    SELECT payor_guid, plan_guid, COUNT(*) AS same_plan_pfc_count
    FROM eligible_pfcs
    WHERE plan_guid IS NOT NULL
    GROUP BY payor_guid, plan_guid
),
representative_candidates AS (
    SELECT
        c.*,
        i.exact_candidate_count,
        i.null_candidate_count,
        i.other_candidate_count,
        NVL(s.same_plan_pfc_count, 0) AS same_plan_pfc_count,
        CASE
            WHEN i.exact_candidate_count > 0 AND i.null_candidate_count > 0
                THEN 1
            WHEN i.exact_candidate_count > 1 THEN 2
            WHEN i.exact_candidate_count = 0 AND i.null_candidate_count > 1
                THEN 3
            WHEN c.relationship_category = 'OTHER_PLAN_HER' THEN 4
            WHEN NVL(s.same_plan_pfc_count, 0) > 1 THEN 5
            WHEN c.template_context_status = 'BILLING_FORM_VALID'
             AND (c.pfc_form_template_guid IS NOT NULL
                  OR c.pfc_user_form_template_guid IS NOT NULL) THEN 6
            WHEN c.template_context_status = 'STALE_TEMPLATE_ASSOCIATION'
                THEN 7
            WHEN c.her_type_of_bill IS NOT NULL THEN 8
            WHEN c.hef_count > 20 THEN 9
            WHEN c.pfc_plan_guid IS NOT NULL
             AND c.relationship_category = 'EXACT_PLAN' THEN 10
            WHEN c.relationship_category = 'NULL_HER_FOR_PLAN_PFC' THEN 11
            WHEN c.pfc_plan_guid IS NULL
             AND c.relationship_category = 'EXACT_PLAN' THEN 12
            ELSE 99
        END AS representative_priority,
        CASE
            WHEN i.exact_candidate_count > 0 AND i.null_candidate_count > 0
                THEN 'SAME_IDENTITY_EXACT_AND_NULL'
            WHEN i.exact_candidate_count > 1
                THEN 'MULTIPLE_EXACT_CANDIDATES'
            WHEN i.exact_candidate_count = 0 AND i.null_candidate_count > 1
                THEN 'MULTIPLE_NULL_FALLBACK_CANDIDATES'
            WHEN c.relationship_category = 'OTHER_PLAN_HER'
                THEN 'OTHER_PLAN_HER'
            WHEN NVL(s.same_plan_pfc_count, 0) > 1
                THEN 'MULTIPLE_PFCS_SAME_PLAN'
            WHEN c.template_context_status = 'BILLING_FORM_VALID'
             AND (c.pfc_form_template_guid IS NOT NULL
                  OR c.pfc_user_form_template_guid IS NOT NULL)
                THEN 'TEMPLATELESS_HER_FOR_TEMPLATED_PFC'
            WHEN c.template_context_status = 'STALE_TEMPLATE_ASSOCIATION'
                THEN 'STALE_TEMPLATE_ASSOCIATION'
            WHEN c.her_type_of_bill IS NOT NULL
                THEN 'HER_TYPE_OF_BILL_PRESENT'
            WHEN c.hef_count > 20 THEN 'SUBSTANTIAL_HEF_CHILDREN'
            WHEN c.pfc_plan_guid IS NOT NULL
             AND c.relationship_category = 'EXACT_PLAN'
                THEN 'PLAN_PFC_EXACT_HER'
            WHEN c.relationship_category = 'NULL_HER_FOR_PLAN_PFC'
                THEN 'PLAN_PFC_NULL_FALLBACK_HER'
            ELSE 'NO_PLAN_PFC_NULL_HER'
        END AS representative_reason
    FROM context_base c
    LEFT JOIN logical_identity_counts i
      ON i.payor_guid = c.payor_guid
     AND i.pfc_guid = c.pfc_guid
     AND i.record_type_code = c.record_type_code
     AND i.template_context_status = c.template_context_status
     AND i.logical_template_context = c.logical_template_context
    LEFT JOIN same_plan_pfc_counts s
      ON s.payor_guid = c.payor_guid
     AND s.plan_guid = c.pfc_plan_guid
),
representative_reason_ranked AS (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY representative_reason
            ORDER BY payor_guid, pfc_guid, record_type_code,
                     electronic_rec_guid
        ) AS reason_rank
    FROM representative_candidates r
    WHERE representative_priority < 99
),
representative_ranked AS (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            ORDER BY representative_priority,
                     payor_guid, pfc_guid, record_type_code,
                     electronic_rec_guid
        ) AS representative_rank
    FROM representative_reason_ranked r
    WHERE reason_rank <= 2
)
SELECT *
FROM (
    /* 3. PFC_STRUCTURAL_PATTERNS: presence combinations. */
    SELECT
        'PFC_STRUCTURAL_PATTERNS' AS output_section,
        3 AS output_order,
        'PFC_PRESENCE_COMBINATION' AS pattern_scope,
        CAST(NULL AS VARCHAR2(50)) AS pattern_category,
        CASE WHEN p.plan_guid IS NULL THEN 'N' ELSE 'Y' END AS plan_present,
        CAST(NULL AS VARCHAR2(1)) AS type_of_bill_present,
        CASE WHEN p.form_template_guid IS NULL THEN 'N' ELSE 'Y' END
            AS form_template_present,
        CASE WHEN p.user_form_template_guid IS NULL THEN 'N' ELSE 'Y' END
            AS user_template_present,
        CAST(NULL AS VARCHAR2(1)) AS payor_type_present,
        CAST(NULL AS VARCHAR2(20)) AS record_type_code,
        CAST(NULL AS VARCHAR2(40)) AS relationship_category,
        CAST(NULL AS VARCHAR2(40)) AS template_context_status,
        CAST(NULL AS VARCHAR2(40)) AS fallback_pattern,
        CAST(NULL AS VARCHAR2(10)) AS hef_count_bucket,
        COUNT(*) AS pfc_count,
        COUNT(DISTINCT p.payor_guid) AS payor_count,
        CAST(NULL AS NUMBER) AS her_count,
        CAST(NULL AS NUMBER) AS distinct_her_count,
        CAST(NULL AS NUMBER) AS relationship_pair_count,
        CAST(NULL AS NUMBER) AS logical_identity_count,
        COUNT(DISTINCT p.plan_guid) AS distinct_plan_count,
        CAST(NULL AS NUMBER) AS distinct_record_type_count,
        CAST(NULL AS NUMBER) AS plan_populated_her_count,
        CAST(NULL AS NUMBER) AS plan_null_her_count,
        CAST(NULL AS NUMBER) AS template_present_her_count,
        CAST(NULL AS NUMBER) AS type_of_bill_present_her_count,
        CAST(NULL AS NUMBER) AS multiple_exact_candidate_identity_count,
        CAST(NULL AS NUMBER) AS multiple_null_candidate_identity_count,
        CAST(NULL AS NUMBER) AS min_hef_count,
        CAST(NULL AS NUMBER) AS max_hef_count,
        CAST(NULL AS NUMBER) AS avg_hef_count,
        CAST(NULL AS NUMBER) AS representative_rank,
        CAST(NULL AS VARCHAR2(36)) AS payor_guid,
        CAST(NULL AS VARCHAR2(36)) AS pfc_guid,
        CAST(NULL AS VARCHAR2(36)) AS pfc_plan_guid,
        CAST(NULL AS VARCHAR2(36)) AS pfc_form_template_guid,
        CAST(NULL AS VARCHAR2(36)) AS pfc_user_template_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_electronic_rec_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_plan_guid,
        CAST(NULL AS VARCHAR2(20)) AS her_record_type_code,
        CAST(NULL AS VARCHAR2(36)) AS her_form_template_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_user_template_guid,
        CAST(NULL AS NUMBER) AS hef_count,
        CAST(NULL AS VARCHAR2(50)) AS representative_reason
    FROM eligible_pfcs p
    GROUP BY
        CASE WHEN p.plan_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN p.form_template_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN p.user_form_template_guid IS NULL THEN 'N' ELSE 'Y' END
    UNION ALL
    /* 3. PFC_STRUCTURAL_PATTERNS: payor topology counts. */
    SELECT
        'PFC_STRUCTURAL_PATTERNS', 3, 'PAYOR_PFC_TOPOLOGY',
        t.pattern_category,
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(20)),
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(10)),
        CAST(NULL AS NUMBER), t.payor_count,
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(50))
    FROM pfc_topology_rows t
    UNION ALL
    /* 4. HER_STRUCTURAL_PATTERNS. */
    SELECT
        'HER_STRUCTURAL_PATTERNS', 4, 'HER_PRESENCE_COMBINATION',
        CAST(NULL AS VARCHAR2(50)),
        CASE WHEN h.plan_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN h.type_of_bill IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN h.form_template_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN h.user_form_template_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN h.payor_type_guid IS NULL THEN 'N' ELSE 'Y' END,
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(10)), CAST(NULL AS NUMBER),
        COUNT(DISTINCT h.payor_guid), COUNT(*), COUNT(*),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        COUNT(DISTINCT h.record_type_code),
        SUM(CASE WHEN h.plan_guid IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN h.plan_guid IS NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN h.form_template_guid IS NOT NULL
                      OR h.user_form_template_guid IS NOT NULL
                 THEN 1 ELSE 0 END),
        SUM(CASE WHEN h.type_of_bill IS NOT NULL THEN 1 ELSE 0 END),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(50))
    FROM payor_hers h
    GROUP BY
        CASE WHEN h.plan_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN h.type_of_bill IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN h.form_template_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN h.user_form_template_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN h.payor_type_guid IS NULL THEN 'N' ELSE 'Y' END
    UNION ALL
    /* 5. PFC_HER_PLAN_PATTERNS: relationship-pair counts. */
    SELECT
        'PFC_HER_PLAN_PATTERNS', 5, 'TEMPLATE_VALID_RELATIONSHIP_PAIRS',
        CAST(NULL AS VARCHAR2(50)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(20)), v.relationship_category,
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(10)),
        COUNT(DISTINCT v.pfc_guid), COUNT(DISTINCT v.payor_guid),
        CAST(NULL AS NUMBER), COUNT(DISTINCT v.electronic_rec_guid),
        COUNT(*), CAST(NULL AS NUMBER),
        COUNT(DISTINCT v.pfc_plan_guid),
        COUNT(DISTINCT v.record_type_code),
        COUNT(DISTINCT CASE WHEN v.her_plan_guid IS NOT NULL
                            THEN v.electronic_rec_guid END),
        COUNT(DISTINCT CASE WHEN v.her_plan_guid IS NULL
                            THEN v.electronic_rec_guid END),
        COUNT(DISTINCT CASE WHEN v.her_form_template_guid IS NOT NULL
                                  OR v.her_user_form_template_guid IS NOT NULL
                            THEN v.electronic_rec_guid END),
        COUNT(DISTINCT CASE WHEN v.her_type_of_bill IS NOT NULL
                            THEN v.electronic_rec_guid END),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(50))
    FROM valid_contexts v
    GROUP BY v.relationship_category
    UNION ALL
    /* 5. PFC_HER_PLAN_PATTERNS: PFC/payor context presence counts. */
    SELECT
        'PFC_HER_PLAN_PATTERNS', 5, 'PFC_CONTEXT_PRESENCE',
        t.pattern_category,
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(20)),
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(10)),
        t.pfc_count, t.payor_count,
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(50))
    FROM pfc_context_pattern_rows t
    UNION ALL
    /* 6. EXACT_VS_NULL_FALLBACK_PATTERNS. */
    SELECT
        'EXACT_VS_NULL_FALLBACK_PATTERNS', 6,
        'PLAN_PFC_LOGICAL_IDENTITIES', CAST(NULL AS VARCHAR2(50)),
        CAST('Y' AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(20)),
        CAST(NULL AS VARCHAR2(40)), i.template_context_status,
        i.fallback_pattern, CAST(NULL AS VARCHAR2(10)),
        COUNT(DISTINCT i.pfc_guid), COUNT(DISTINCT i.payor_guid),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        COUNT(*), COUNT(DISTINCT i.pfc_plan_guid),
        COUNT(DISTINCT i.record_type_code),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER),
        SUM(CASE WHEN i.exact_candidate_count > 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN i.exact_candidate_count = 0
                       AND i.null_candidate_count > 1
                 THEN 1 ELSE 0 END),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(50))
    FROM logical_identity_classified i
    GROUP BY i.template_context_status, i.fallback_pattern
    UNION ALL
    /* 7. TEMPLATE_CONTEXT_PATTERNS. */
    SELECT
        'TEMPLATE_CONTEXT_PATTERNS', 7, 'PFC_HER_TEMPLATE_PAIRS',
        CAST(NULL AS VARCHAR2(50)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(40)),
        c.template_context_status, CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(10)),
        COUNT(DISTINCT c.pfc_guid), COUNT(DISTINCT c.payor_guid),
        CAST(NULL AS NUMBER), COUNT(DISTINCT c.electronic_rec_guid),
        COUNT(*), CAST(NULL AS NUMBER),
        COUNT(DISTINCT c.pfc_plan_guid),
        COUNT(DISTINCT c.record_type_code),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(50))
    FROM context_base c
    GROUP BY c.template_context_status
    UNION ALL
    /* 8. HER_HEF_RELATIONSHIP_PATTERNS: bucket distributions. */
    SELECT
        'HER_HEF_RELATIONSHIP_PATTERNS', 8, 'HEF_COUNT_DISTRIBUTION',
        h.pattern_category,
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(20)),
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(40)), h.hef_count_bucket,
        CAST(NULL AS NUMBER), COUNT(DISTINCT h.payor_guid),
        COUNT(*), COUNT(*), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), COUNT(DISTINCT h.record_type_code),
        SUM(CASE WHEN h.plan_guid IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN h.plan_guid IS NULL THEN 1 ELSE 0 END),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        MIN(h.hef_count), MAX(h.hef_count), ROUND(AVG(h.hef_count), 2),
        CAST(NULL AS NUMBER), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(50))
    FROM her_hef_bucketed h
    GROUP BY h.pattern_category, h.hef_count_bucket
    UNION ALL
    /* 8. HER_HEF_RELATIONSHIP_PATTERNS: population summary. */
    SELECT
        'HER_HEF_RELATIONSHIP_PATTERNS', 8, 'HEF_COUNT_SUMMARY',
        h.pattern_category,
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(20)),
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(10)),
        CAST(NULL AS NUMBER), COUNT(DISTINCT h.payor_guid),
        COUNT(*), COUNT(*), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), COUNT(DISTINCT h.record_type_code),
        SUM(CASE WHEN h.plan_guid IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN h.plan_guid IS NULL THEN 1 ELSE 0 END),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        MIN(h.hef_count), MAX(h.hef_count), ROUND(AVG(h.hef_count), 2),
        CAST(NULL AS NUMBER), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(50))
    FROM her_hef_populations h
    GROUP BY h.pattern_category
    UNION ALL
    /* 9. RECORD_TYPE_PATTERNS. */
    SELECT
        'RECORD_TYPE_PATTERNS', 9, 'PAYOR_HER_RECORD_TYPE',
        CAST(NULL AS VARCHAR2(50)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(1)),
        h.record_type_code, CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(40)),
        CAST(NULL AS VARCHAR2(10)), CAST(NULL AS NUMBER),
        COUNT(DISTINCT h.payor_guid), COUNT(*), COUNT(*),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER),
        SUM(CASE WHEN h.plan_guid IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN h.plan_guid IS NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN h.form_template_guid IS NOT NULL
                      OR h.user_form_template_guid IS NOT NULL
                 THEN 1 ELSE 0 END),
        SUM(CASE WHEN h.type_of_bill IS NOT NULL THEN 1 ELSE 0 END),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        MIN(h.hef_count), MAX(h.hef_count), ROUND(AVG(h.hef_count), 2),
        CAST(NULL AS NUMBER), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(20)), CAST(NULL AS VARCHAR2(36)),
        CAST(NULL AS VARCHAR2(36)), CAST(NULL AS NUMBER),
        CAST(NULL AS VARCHAR2(50))
    FROM her_with_hef h
    GROUP BY h.record_type_code
    UNION ALL
    /* 10. REPRESENTATIVE_CONTEXTS: technical identifiers only, max 25. */
    SELECT
        'REPRESENTATIVE_CONTEXTS', 10, 'BOUNDED_TECHNICAL_EXAMPLE',
        CAST(NULL AS VARCHAR2(50)),
        CASE WHEN r.pfc_plan_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN r.her_type_of_bill IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN r.her_form_template_guid IS NULL THEN 'N' ELSE 'Y' END,
        CASE WHEN r.her_user_form_template_guid IS NULL THEN 'N' ELSE 'Y' END,
        CAST(NULL AS VARCHAR2(1)), CAST(NULL AS VARCHAR2(20)),
        r.relationship_category, r.template_context_status,
        CAST(NULL AS VARCHAR2(40)), CAST(NULL AS VARCHAR2(10)),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        CAST(NULL AS NUMBER), CAST(NULL AS NUMBER),
        r.representative_rank, r.payor_guid, r.pfc_guid, r.pfc_plan_guid,
        r.pfc_form_template_guid, r.pfc_user_form_template_guid,
        r.electronic_rec_guid, r.her_plan_guid, r.record_type_code,
        r.her_form_template_guid, r.her_user_form_template_guid,
        r.hef_count, r.representative_reason
    FROM representative_ranked r
    WHERE r.representative_rank <= 25
) report_output
ORDER BY
    report_output.output_order,
    report_output.pattern_scope,
    report_output.pattern_category,
    report_output.record_type_code,
    report_output.relationship_category,
    report_output.template_context_status,
    report_output.fallback_pattern,
    report_output.hef_count_bucket,
    report_output.representative_rank;
