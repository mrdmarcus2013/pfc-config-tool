/*
 * Human-readable reference query for Script 2.
 *
 * Approved correction: PAYOR_TYPE_GUID is resolved from PAYORS through
 * PFC.PAYOR_GUID. PFC.PAYOR_TYPE_GUID is intentionally not referenced.
 */
WITH params AS (
    SELECT
        'PUT_PAYOR_GUID_HERE'       AS payor_guid,
        'PUT_RECORD_TYPE_CODE_HERE' AS record_type_code,
        NULL                        AS plan_guid
    FROM dual
),
selected_pfc AS (
    SELECT *
    FROM (
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
            ROW_NUMBER() OVER (
                ORDER BY p.cpd_start_date DESC NULLS LAST
            ) AS rn
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
    )
    WHERE rn = 1
)
SELECT
    /* PFC and authoritative payor type */
    p.pfc_guid,
    p.payor_guid,
    p.plan_guid,
    p.payor_type_guid,
    p.billing_form_code,
    p.form_template_guid,
    p.user_form_template_guid,
    p.cpd_start_date,
    p.cpd_end_date,

    /* HER */
    h.electronic_rec_guid,
    h.record_type_code,
    h.record_name,
    h.payor_guid              AS her_payor_guid,
    h.payor_type_guid         AS her_payor_type_guid,
    h.form_template_guid      AS her_form_template_guid,
    h.user_form_template_guid AS her_user_form_template_guid,
    h.sto_proc_name           AS her_sto_proc_name,

    /* HEF */
    f.field_number,
    f.field_name,
    f.sto_proc_name           AS hef_sto_proc_name,
    f.hard_coded_data         AS hef_hard_coded_data,
    f.position_from,
    f.position_thru,
    f.order_num
FROM selected_pfc p
CROSS JOIN params x
JOIN hcfa_electronic_records h
  ON h.billing_form_code = p.billing_form_code
 AND h.record_type_code = x.record_type_code
LEFT JOIN hcfa_electronic_fields f
  ON f.electronic_rec_guid = h.electronic_rec_guid
WHERE (
        h.payor_guid = p.payor_guid
        OR h.payor_guid IS NULL
      )
  AND h.plan_guid IS NULL
  AND h.type_of_bill IS NULL
  AND (
        h.payor_type_guid = p.payor_type_guid
        OR h.payor_type_guid IS NULL
      )
  AND (
        h.form_template_guid = p.form_template_guid
        OR h.form_template_guid IS NULL
      )
  AND (
        h.user_form_template_guid = p.user_form_template_guid
        OR h.user_form_template_guid IS NULL
      )
ORDER BY
    CASE
        WHEN h.payor_guid = p.payor_guid THEN 1
        WHEN h.user_form_template_guid = p.user_form_template_guid
             AND h.user_form_template_guid IS NOT NULL THEN 2
        WHEN h.form_template_guid = p.form_template_guid
             AND h.form_template_guid IS NOT NULL THEN 3
        ELSE 4
    END,
    h.electronic_rec_guid,
    f.order_num,
    f.field_number;
