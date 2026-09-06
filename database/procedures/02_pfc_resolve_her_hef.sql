CREATE OR REPLACE PROCEDURE pfc_resolve_her_hef (
    p_payor_guid       IN pfc.payor_guid%TYPE,
    p_plan_guid        IN pfc.plan_guid%TYPE DEFAULT NULL,
    p_record_type_code IN hcfa_electronic_records.record_type_code%TYPE,
    p_results          OUT SYS_REFCURSOR
)
AUTHID DEFINER
IS
    c_err_clone_source_missing CONSTANT PLS_INTEGER := -20020;
    c_err_clone_source_tie     CONSTANT PLS_INTEGER := -20021;

    l_pfc                        pfc_config_internal.t_pfc_resolution;
    l_clone_source_guid          hcfa_electronic_records.electronic_rec_guid%TYPE;
    l_clone_template_rank        PLS_INTEGER;
    l_clone_payor_type_rank      PLS_INTEGER;
    l_top_clone_source_count     PLS_INTEGER := 0;
    l_payor_specific_her_count   PLS_INTEGER;
BEGIN
    pfc_config_internal.resolve_pfc(
        p_payor_guid => p_payor_guid,
        p_plan_guid  => p_plan_guid,
        p_resolution => l_pfc
    );

    FOR candidate IN (
        SELECT
            ranked_her.electronic_rec_guid,
            ranked_her.template_rank,
            ranked_her.payor_type_rank
        FROM (
            SELECT
                h.electronic_rec_guid,
                CASE
                    WHEN h.payor_guid = l_pfc.payor_guid THEN 0
                        WHEN h.user_form_template_guid IS NOT NULL THEN 1
                    WHEN h.form_template_guid IS NOT NULL THEN 2
                    ELSE 3
                END AS template_rank,
                CASE
                    WHEN h.payor_type_guid = l_pfc.payor_type_guid
                         AND h.payor_type_guid IS NOT NULL THEN 1
                    ELSE 2
                END AS payor_type_rank
            FROM hcfa_electronic_records h
            WHERE h.billing_form_code = l_pfc.billing_form_code
              AND h.record_type_code = p_record_type_code
              AND (h.payor_guid IS NULL OR (p_plan_guid IS NOT NULL AND h.payor_guid = l_pfc.payor_guid))
              AND h.plan_guid IS NULL
              AND h.type_of_bill IS NULL
              AND (
                    h.payor_type_guid = l_pfc.payor_type_guid
                    OR h.payor_type_guid IS NULL
                  )
              AND (
                    h.form_template_guid = l_pfc.form_template_guid
                    OR h.form_template_guid IS NULL
                  )
              AND (
                    h.user_form_template_guid = l_pfc.user_form_template_guid
                    OR h.user_form_template_guid IS NULL
                  )
        ) ranked_her
        ORDER BY
            ranked_her.template_rank,
            ranked_her.payor_type_rank
    ) LOOP
        IF l_top_clone_source_count = 0 THEN
            l_clone_source_guid := candidate.electronic_rec_guid;
            l_clone_template_rank := candidate.template_rank;
            l_clone_payor_type_rank := candidate.payor_type_rank;
            l_top_clone_source_count := 1;
        ELSIF candidate.template_rank = l_clone_template_rank
              AND candidate.payor_type_rank = l_clone_payor_type_rank THEN
            l_top_clone_source_count := l_top_clone_source_count + 1;
        ELSE
            EXIT;
        END IF;
    END LOOP;

    IF l_top_clone_source_count = 0 THEN
        RAISE_APPLICATION_ERROR(
            c_err_clone_source_missing,
            'No eligible generic HER clone source was found.'
        );
    END IF;

    IF l_top_clone_source_count > 1 THEN
        RAISE_APPLICATION_ERROR(
            c_err_clone_source_tie,
            'Multiple generic HER rows share the highest clone-source rank.'
        );
    END IF;

    SELECT COUNT(*)
    INTO l_payor_specific_her_count
    FROM hcfa_electronic_records h
    WHERE h.billing_form_code = l_pfc.billing_form_code
      AND h.record_type_code = p_record_type_code
      AND h.payor_guid = l_pfc.payor_guid
      AND (h.plan_guid = p_plan_guid OR (h.plan_guid IS NULL AND p_plan_guid IS NULL))
      AND h.type_of_bill IS NULL
      AND (
            h.payor_type_guid = l_pfc.payor_type_guid
            OR h.payor_type_guid IS NULL
          )
      AND (
            h.form_template_guid = l_pfc.form_template_guid
            OR h.form_template_guid IS NULL
          )
      AND (
            h.user_form_template_guid = l_pfc.user_form_template_guid
            OR h.user_form_template_guid IS NULL
          );

    OPEN p_results FOR
        SELECT
            l_pfc.pfc_guid AS pfc_guid,
            l_pfc.payor_guid AS payor_guid,
            l_pfc.plan_guid AS plan_guid,
            l_pfc.payor_type_guid AS payor_type_guid,
            l_pfc.billing_form_code AS billing_form_code,
            l_pfc.form_template_guid AS form_template_guid,
            l_pfc.user_form_template_guid AS user_form_template_guid,
            l_pfc.cpd_start_date AS cpd_start_date,
            l_pfc.cpd_end_date AS cpd_end_date,
            CASE
                WHEN l_payor_specific_her_count > 0 THEN 'Y'
                ELSE 'N'
            END AS payor_specific_her_exists,
            CASE
                WHEN h.payor_guid = l_pfc.payor_guid
                  AND (h.plan_guid = p_plan_guid OR (h.plan_guid IS NULL AND p_plan_guid IS NULL)) THEN 'PAYOR_SPECIFIC'
                ELSE 'GENERIC'
            END AS her_scope_code,
            CASE
                WHEN h.electronic_rec_guid = l_clone_source_guid THEN 'Y'
                ELSE 'N'
            END AS is_clone_source,
            CASE
                WHEN h.payor_guid IS NULL THEN
                    CASE
                        WHEN h.user_form_template_guid IS NOT NULL THEN 1
                        WHEN h.form_template_guid IS NOT NULL THEN 2
                        ELSE 3
                    END
                ELSE NULL
            END AS clone_template_rank,
            CASE
                WHEN h.payor_guid IS NULL
                     AND h.payor_type_guid = l_pfc.payor_type_guid
                     AND h.payor_type_guid IS NOT NULL THEN 1
                WHEN h.payor_guid IS NULL THEN 2
                ELSE NULL
            END AS clone_payor_type_rank,
            h.electronic_rec_guid AS electronic_rec_guid,
            h.record_type_code AS record_type_code,
            h.record_name AS record_name,
            h.payor_guid AS her_payor_guid,
            h.payor_type_guid AS her_payor_type_guid,
            h.form_template_guid AS her_form_template_guid,
            h.user_form_template_guid AS her_user_form_template_guid,
            h.sto_proc_name AS her_sto_proc_name,
            f.field_number AS field_number,
            f.field_name AS field_name,
            f.sto_proc_name AS hef_sto_proc_name,
            f.hard_coded_data AS hef_hard_coded_data,
            f.position_from AS position_from,
            f.position_thru AS position_thru,
            f.order_num AS order_num
        FROM hcfa_electronic_records h
        LEFT JOIN hcfa_electronic_fields f
            ON f.electronic_rec_guid = h.electronic_rec_guid
        WHERE h.billing_form_code = l_pfc.billing_form_code
          AND h.record_type_code = p_record_type_code
          AND (
                h.payor_guid = l_pfc.payor_guid
                OR h.payor_guid IS NULL
              )
          AND (h.plan_guid IS NULL OR (h.payor_guid = l_pfc.payor_guid AND h.plan_guid = p_plan_guid))
          AND h.type_of_bill IS NULL
          AND (
                h.payor_type_guid = l_pfc.payor_type_guid
                OR h.payor_type_guid IS NULL
              )
          AND (
                h.form_template_guid = l_pfc.form_template_guid
                OR h.form_template_guid IS NULL
              )
          AND (
                h.user_form_template_guid = l_pfc.user_form_template_guid
                OR h.user_form_template_guid IS NULL
              )
        ORDER BY
            CASE
                WHEN h.payor_guid = l_pfc.payor_guid THEN 1
                ELSE 2
            END,
            CASE
                WHEN h.electronic_rec_guid = l_clone_source_guid THEN 1
                ELSE 2
            END,
            CASE
                WHEN h.user_form_template_guid IS NOT NULL THEN 1
                WHEN h.form_template_guid IS NOT NULL THEN 2
                ELSE 3
            END,
            CASE
                WHEN h.payor_type_guid = l_pfc.payor_type_guid
                     AND h.payor_type_guid IS NOT NULL THEN 1
                ELSE 2
            END,
            h.electronic_rec_guid,
            f.order_num,
            f.field_number;
END pfc_resolve_her_hef;
/
