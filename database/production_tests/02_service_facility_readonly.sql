/*
 * Box 77 - Service Facility Info production discovery.
 *
 * Edit only PAYOR_GUID and PLAN_GUID in params. Leave PLAN_GUID as NULL when
 * resolving the payor-level PFC. This statement reads data only.
 */
WITH params AS (
    SELECT
        'PUT_PAYOR_GUID_HERE' AS payor_guid, -- PAYOR_GUID
        NULL                  AS plan_guid   -- PLAN_GUID: NULL or 'PUT_PLAN_GUID_HERE'
    FROM dual
),
targets AS (
    SELECT 'NM1' AS target_segment, 'D2310E2500NM1343' AS record_type_code
    FROM dual
    UNION ALL
    SELECT 'N3', 'D2310E2650N3346'
    FROM dual
    UNION ALL
    SELECT 'N4', 'D2310E2700N4347'
    FROM dual
),
expected_hefs AS (
    SELECT 'NM1' AS target_segment, '01' AS expected_field_number,
           'KEEP' AS expected_sto_proc_action,
           CAST(NULL AS VARCHAR2(30)) AS expected_sto_proc_value,
           'SET' AS expected_hard_coded_action,
           '77' AS expected_hard_coded_value
    FROM dual
    UNION ALL
    SELECT 'NM1', '02', 'KEEP', NULL, 'SET', '2'
    FROM dual
    UNION ALL
    SELECT 'NM1', '03', 'SET', 'G_ORGANIZATION_NAME', 'KEEP', NULL
    FROM dual
    UNION ALL
    SELECT 'NM1', '09', 'SET', 'G_FACILITY_NPI', 'KEEP', NULL
    FROM dual
    UNION ALL
    SELECT 'N3', '01', 'SET', 'G_CARE_LOCATION_ADDR1', 'KEEP', NULL
    FROM dual
    UNION ALL
    SELECT 'N3', '02', 'SET', 'G_CARE_LOCATION_ADDR2', 'KEEP', NULL
    FROM dual
    UNION ALL
    SELECT 'N4', '01', 'SET', 'G_CARE_LOCATION_CITY', 'KEEP', NULL
    FROM dual
    UNION ALL
    SELECT 'N4', '02', 'SET', 'G_CARE_LOCATION_STATE', 'KEEP', NULL
    FROM dual
    UNION ALL
    SELECT 'N4', '03', 'SET', 'G_CARE_LOCATION_ZIP', 'KEEP', NULL
    FROM dual
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
                p.plan_guid = x.plan_guid
                OR p.plan_guid IS NULL
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
        CASE
            WHEN COUNT(p.pfc_guid) = 0 THEN 'MISSING'
            WHEN COUNT(p.pfc_guid) > 1 THEN 'AMBIGUOUS_NEWEST_DATE'
            ELSE 'RESOLVED'
        END AS pfc_status,
        COUNT(p.pfc_guid) AS winning_pfc_count,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.pfc_guid) END AS pfc_guid,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.plan_guid) END
            AS pfc_plan_guid,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.payor_type_guid) END
            AS payor_type_guid,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.billing_form_code) END
            AS billing_form_code,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.form_template_guid) END
            AS form_template_guid,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.user_form_template_guid) END
            AS user_form_template_guid,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.cpd_start_date) END
            AS cpd_start_date,
        CASE WHEN COUNT(p.pfc_guid) = 1 THEN MAX(p.cpd_end_date) END
            AS cpd_end_date
    FROM params x
    LEFT JOIN winning_pfc p
      ON 1 = 1
    GROUP BY x.payor_guid, x.plan_guid
),
target_context AS (
    SELECT
        t.target_segment,
        t.record_type_code,
        p.*
    FROM targets t
    CROSS JOIN pfc_resolution p
),
source_candidates AS (
    SELECT
        c.target_segment,
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
            WHEN h.payor_type_guid = c.payor_type_guid
                 AND h.payor_type_guid IS NOT NULL THEN 1
            ELSE 2
        END AS payor_type_rank,
        DENSE_RANK() OVER (
            PARTITION BY c.target_segment
            ORDER BY
                CASE
                    WHEN h.user_form_template_guid IS NOT NULL THEN 1
                    WHEN h.form_template_guid IS NOT NULL THEN 2
                    ELSE 3
                END,
                CASE
                    WHEN h.payor_type_guid = c.payor_type_guid
                         AND h.payor_type_guid IS NOT NULL THEN 1
                    ELSE 2
                END
        ) AS source_rank
    FROM target_context c
    JOIN hcfa_electronic_records h
      ON h.billing_form_code = c.billing_form_code
     AND h.record_type_code = c.record_type_code
    WHERE c.pfc_status = 'RESOLVED'
      AND h.payor_guid IS NULL
      AND h.plan_guid IS NULL
      AND h.type_of_bill IS NULL
      AND (
            h.payor_type_guid = c.payor_type_guid
            OR h.payor_type_guid IS NULL
          )
      AND (
            h.form_template_guid = c.form_template_guid
            OR h.form_template_guid IS NULL
          )
      AND (
            h.user_form_template_guid = c.user_form_template_guid
            OR h.user_form_template_guid IS NULL
          )
),
best_source_candidates AS (
    SELECT s.*
    FROM source_candidates s
    WHERE s.source_rank = 1
),
source_resolution AS (
    SELECT
        c.target_segment,
        c.record_type_code,
        c.pfc_guid,
        c.pfc_plan_guid,
        c.payor_guid,
        c.requested_plan_guid,
        c.payor_type_guid,
        c.billing_form_code,
        c.form_template_guid AS pfc_form_template_guid,
        c.user_form_template_guid AS pfc_user_form_template_guid,
        c.cpd_start_date,
        c.cpd_end_date,
        c.pfc_status,
        c.winning_pfc_count,
        CASE
            WHEN c.pfc_status = 'MISSING' THEN 'BLOCKED_PFC_MISSING'
            WHEN c.pfc_status = 'AMBIGUOUS_NEWEST_DATE'
                THEN 'BLOCKED_PFC_AMBIGUOUS'
            WHEN COUNT(s.electronic_rec_guid) = 0 THEN 'MISSING'
            WHEN COUNT(s.electronic_rec_guid) > 1 THEN 'AMBIGUOUS'
            ELSE 'RESOLVED'
        END AS source_status,
        COUNT(s.electronic_rec_guid) AS best_source_count,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.electronic_rec_guid) END
            AS source_electronic_rec_guid,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.form_template_guid) END
            AS source_form_template_guid,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.user_form_template_guid) END
            AS source_user_form_template_guid,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.payor_type_guid) END
            AS source_payor_type_guid,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.sto_proc_name) END
            AS source_her_sto_proc_name,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.template_rank) END
            AS source_template_rank,
        CASE WHEN COUNT(s.electronic_rec_guid) = 1
            THEN MAX(s.payor_type_rank) END
            AS source_payor_type_rank
    FROM target_context c
    LEFT JOIN best_source_candidates s
      ON s.target_segment = c.target_segment
    GROUP BY
        c.target_segment,
        c.record_type_code,
        c.pfc_guid,
        c.pfc_plan_guid,
        c.payor_guid,
        c.requested_plan_guid,
        c.payor_type_guid,
        c.billing_form_code,
        c.form_template_guid,
        c.user_form_template_guid,
        c.cpd_start_date,
        c.cpd_end_date,
        c.pfc_status,
        c.winning_pfc_count
),
existing_payor_hers AS (
    SELECT
        c.target_segment,
        h.electronic_rec_guid,
        h.payor_guid,
        h.payor_type_guid,
        h.plan_guid,
        h.type_of_bill,
        h.form_template_guid,
        h.user_form_template_guid,
        h.sto_proc_name
    FROM target_context c
    JOIN hcfa_electronic_records h
      ON h.payor_guid = c.payor_guid
     AND h.billing_form_code = c.billing_form_code
     AND h.record_type_code = c.record_type_code
    WHERE c.pfc_status = 'RESOLVED'
),
existing_counts AS (
    SELECT
        c.target_segment,
        COUNT(DISTINCT h.electronic_rec_guid) AS existing_payor_her_count,
        COUNT(f.electronic_rec_guid) AS existing_payor_hef_count
    FROM target_context c
    LEFT JOIN existing_payor_hers h
      ON h.target_segment = c.target_segment
    LEFT JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
    GROUP BY c.target_segment
),
managed_source_hefs AS (
    SELECT
        s.target_segment,
        s.source_electronic_rec_guid,
        s.source_payor_type_guid,
        s.source_form_template_guid,
        s.source_user_form_template_guid,
        s.source_her_sto_proc_name,
        e.expected_field_number,
        e.expected_sto_proc_action,
        e.expected_sto_proc_value,
        e.expected_hard_coded_action,
        e.expected_hard_coded_value,
        COUNT(f.electronic_rec_guid) AS source_hef_match_count,
        CASE WHEN COUNT(f.electronic_rec_guid) = 1
            THEN MAX(f.field_number) END AS field_number,
        CASE WHEN COUNT(f.electronic_rec_guid) = 1
            THEN MAX(f.field_name) END AS field_name,
        CASE WHEN COUNT(f.electronic_rec_guid) = 1
            THEN MAX(f.sto_proc_name) END AS hef_sto_proc_name,
        CASE WHEN COUNT(f.electronic_rec_guid) = 1
            THEN MAX(f.hard_coded_data) END AS hef_hard_coded_data,
        CASE WHEN COUNT(f.electronic_rec_guid) = 1
            THEN MAX(f.position_from) END AS position_from,
        CASE WHEN COUNT(f.electronic_rec_guid) = 1
            THEN MAX(f.position_thru) END AS position_thru,
        CASE WHEN COUNT(f.electronic_rec_guid) = 1
            THEN MAX(f.order_num) END AS order_num
    FROM source_resolution s
    JOIN expected_hefs e
      ON e.target_segment = s.target_segment
    LEFT JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = s.source_electronic_rec_guid
     AND f.field_number = e.expected_field_number
    WHERE s.source_status = 'RESOLVED'
    GROUP BY
        s.target_segment,
        s.source_electronic_rec_guid,
        s.source_payor_type_guid,
        s.source_form_template_guid,
        s.source_user_form_template_guid,
        s.source_her_sto_proc_name,
        e.expected_field_number,
        e.expected_sto_proc_action,
        e.expected_sto_proc_value,
        e.expected_hard_coded_action,
        e.expected_hard_coded_value
),
source_expected_rows AS (
    SELECT
        m.target_segment,
        1 AS scope_sort,
        'SOURCE' AS her_scope,
        m.source_electronic_rec_guid AS electronic_rec_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_payor_guid,
        m.source_payor_type_guid AS her_payor_type_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_plan_guid,
        CAST(NULL AS VARCHAR2(3)) AS her_type_of_bill,
        m.source_form_template_guid AS her_form_template_guid,
        m.source_user_form_template_guid AS her_user_form_template_guid,
        m.source_her_sto_proc_name AS her_sto_proc_name,
        m.field_number,
        m.field_name,
        m.hef_sto_proc_name,
        m.hef_hard_coded_data,
        m.position_from,
        m.position_thru,
        m.order_num,
        m.expected_field_number,
        m.expected_sto_proc_action AS expected_hef_sto_proc_action,
        m.expected_sto_proc_value AS expected_hef_sto_proc_name,
        m.expected_hard_coded_action AS expected_hef_hard_coded_action,
        m.expected_hard_coded_value AS expected_hef_hard_coded_data,
        m.source_hef_match_count,
        CASE
            WHEN m.source_hef_match_count = 0 THEN 'MISSING_SOURCE_HEF'
            WHEN m.source_hef_match_count > 1 THEN 'AMBIGUOUS_SOURCE_HEF'
            WHEN (
                    m.expected_sto_proc_action = 'KEEP'
                    OR (
                        m.expected_sto_proc_action = 'SET'
                        AND DECODE(
                            m.hef_sto_proc_name,
                            m.expected_sto_proc_value,
                            1,
                            0
                        ) = 1
                    )
                    OR (
                        m.expected_sto_proc_action = 'CLEAR'
                        AND m.hef_sto_proc_name IS NULL
                    )
                 )
             AND (
                    m.expected_hard_coded_action = 'KEEP'
                    OR (
                        m.expected_hard_coded_action = 'SET'
                        AND DECODE(
                            m.hef_hard_coded_data,
                            m.expected_hard_coded_value,
                            1,
                            0
                        ) = 1
                    )
                    OR (
                        m.expected_hard_coded_action = 'CLEAR'
                        AND m.hef_hard_coded_data IS NULL
                    )
                 ) THEN 'MATCH'
            ELSE 'MISMATCH'
        END AS source_hef_validation_status
    FROM managed_source_hefs m
),
source_unmanaged_rows AS (
    SELECT
        s.target_segment,
        1 AS scope_sort,
        'SOURCE' AS her_scope,
        s.source_electronic_rec_guid AS electronic_rec_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_payor_guid,
        s.source_payor_type_guid AS her_payor_type_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_plan_guid,
        CAST(NULL AS VARCHAR2(3)) AS her_type_of_bill,
        s.source_form_template_guid AS her_form_template_guid,
        s.source_user_form_template_guid AS her_user_form_template_guid,
        s.source_her_sto_proc_name AS her_sto_proc_name,
        f.field_number,
        f.field_name,
        f.sto_proc_name AS hef_sto_proc_name,
        f.hard_coded_data AS hef_hard_coded_data,
        f.position_from,
        f.position_thru,
        f.order_num,
        CAST(NULL AS VARCHAR2(10)) AS expected_field_number,
        CAST(NULL AS VARCHAR2(10)) AS expected_hef_sto_proc_action,
        CAST(NULL AS VARCHAR2(30)) AS expected_hef_sto_proc_name,
        CAST(NULL AS VARCHAR2(10)) AS expected_hef_hard_coded_action,
        CAST(NULL AS VARCHAR2(128)) AS expected_hef_hard_coded_data,
        CAST(NULL AS NUMBER) AS source_hef_match_count,
        'UNMANAGED_SOURCE_HEF' AS source_hef_validation_status
    FROM source_resolution s
    JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = s.source_electronic_rec_guid
    WHERE s.source_status = 'RESOLVED'
      AND NOT EXISTS (
            SELECT 1
            FROM expected_hefs e
            WHERE e.target_segment = s.target_segment
              AND e.expected_field_number = f.field_number
          )
),
source_status_rows AS (
    SELECT
        s.target_segment,
        2 AS scope_sort,
        'STATUS_ONLY' AS her_scope,
        CAST(NULL AS VARCHAR2(36)) AS electronic_rec_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_payor_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_payor_type_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_plan_guid,
        CAST(NULL AS VARCHAR2(3)) AS her_type_of_bill,
        CAST(NULL AS VARCHAR2(36)) AS her_form_template_guid,
        CAST(NULL AS VARCHAR2(36)) AS her_user_form_template_guid,
        CAST(NULL AS VARCHAR2(30)) AS her_sto_proc_name,
        CAST(NULL AS VARCHAR2(10)) AS field_number,
        CAST(NULL AS VARCHAR2(50)) AS field_name,
        CAST(NULL AS VARCHAR2(30)) AS hef_sto_proc_name,
        CAST(NULL AS VARCHAR2(128)) AS hef_hard_coded_data,
        CAST(NULL AS NUMBER) AS position_from,
        CAST(NULL AS NUMBER) AS position_thru,
        CAST(NULL AS NUMBER) AS order_num,
        CAST(NULL AS VARCHAR2(10)) AS expected_field_number,
        CAST(NULL AS VARCHAR2(10)) AS expected_hef_sto_proc_action,
        CAST(NULL AS VARCHAR2(30)) AS expected_hef_sto_proc_name,
        CAST(NULL AS VARCHAR2(10)) AS expected_hef_hard_coded_action,
        CAST(NULL AS VARCHAR2(128)) AS expected_hef_hard_coded_data,
        CAST(NULL AS NUMBER) AS source_hef_match_count,
        'NOT_EVALUATED' AS source_hef_validation_status
    FROM source_resolution s
    WHERE s.source_status <> 'RESOLVED'
),
existing_payor_rows AS (
    SELECT
        h.target_segment,
        3 AS scope_sort,
        'EXISTING_PAYOR' AS her_scope,
        h.electronic_rec_guid,
        h.payor_guid AS her_payor_guid,
        h.payor_type_guid AS her_payor_type_guid,
        h.plan_guid AS her_plan_guid,
        h.type_of_bill AS her_type_of_bill,
        h.form_template_guid AS her_form_template_guid,
        h.user_form_template_guid AS her_user_form_template_guid,
        h.sto_proc_name AS her_sto_proc_name,
        f.field_number,
        f.field_name,
        f.sto_proc_name AS hef_sto_proc_name,
        f.hard_coded_data AS hef_hard_coded_data,
        f.position_from,
        f.position_thru,
        f.order_num,
        CAST(NULL AS VARCHAR2(10)) AS expected_field_number,
        CAST(NULL AS VARCHAR2(10)) AS expected_hef_sto_proc_action,
        CAST(NULL AS VARCHAR2(30)) AS expected_hef_sto_proc_name,
        CAST(NULL AS VARCHAR2(10)) AS expected_hef_hard_coded_action,
        CAST(NULL AS VARCHAR2(128)) AS expected_hef_hard_coded_data,
        CAST(NULL AS NUMBER) AS source_hef_match_count,
        'NOT_APPLICABLE' AS source_hef_validation_status
    FROM existing_payor_hers h
    LEFT JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
),
report_rows AS (
    SELECT * FROM source_expected_rows
    UNION ALL
    SELECT * FROM source_unmanaged_rows
    UNION ALL
    SELECT * FROM source_status_rows
    UNION ALL
    SELECT * FROM existing_payor_rows
)
SELECT
    s.target_segment,
    s.record_type_code,
    s.pfc_status,
    s.winning_pfc_count,
    s.pfc_guid,
    s.pfc_plan_guid,
    s.payor_guid,
    s.requested_plan_guid,
    s.payor_type_guid,
    s.billing_form_code,
    s.pfc_form_template_guid,
    s.pfc_user_form_template_guid,
    s.cpd_start_date,
    s.cpd_end_date,
    s.source_status,
    s.best_source_count,
    s.source_electronic_rec_guid,
    s.source_form_template_guid,
    s.source_user_form_template_guid,
    s.source_payor_type_guid,
    s.source_her_sto_proc_name,
    s.source_template_rank,
    s.source_payor_type_rank,
    c.existing_payor_her_count,
    c.existing_payor_hef_count,
    r.her_scope,
    r.electronic_rec_guid,
    r.her_payor_guid,
    r.her_payor_type_guid,
    r.her_plan_guid,
    r.her_type_of_bill,
    r.her_form_template_guid,
    r.her_user_form_template_guid,
    r.her_sto_proc_name,
    r.field_number,
    r.field_name,
    r.hef_sto_proc_name,
    r.hef_hard_coded_data,
    r.position_from,
    r.position_thru,
    r.order_num,
    r.expected_field_number,
    r.expected_hef_sto_proc_action,
    r.expected_hef_sto_proc_name,
    r.expected_hef_hard_coded_action,
    r.expected_hef_hard_coded_data,
    r.source_hef_match_count,
    r.source_hef_validation_status
FROM source_resolution s
JOIN existing_counts c
  ON c.target_segment = s.target_segment
JOIN report_rows r
  ON r.target_segment = s.target_segment
ORDER BY
    CASE s.target_segment
        WHEN 'NM1' THEN 1
        WHEN 'N3' THEN 2
        WHEN 'N4' THEN 3
        ELSE 4
    END,
    r.scope_sort,
    r.electronic_rec_guid,
    COALESCE(r.field_number, r.expected_field_number),
    r.order_num;
