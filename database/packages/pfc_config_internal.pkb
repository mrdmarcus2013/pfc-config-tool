CREATE OR REPLACE PACKAGE BODY pfc_config_internal AS
    FUNCTION her_satisfies_safety_invariants (
        p_sto_proc_name IN hcfa_electronic_records.sto_proc_name%TYPE,
        p_mandatory_ind IN hcfa_electronic_records.mandatory_ind%TYPE
    ) RETURN BOOLEAN
    IS
    BEGIN
        RETURN CASE
            WHEN UPPER(TRIM(p_sto_proc_name)) = 'RETURN_1' THEN TRUE
            WHEN UPPER(TRIM(p_mandatory_ind)) = 'N' THEN TRUE
            ELSE FALSE
        END;
    END her_satisfies_safety_invariants;

    PROCEDURE apply_her_safety_invariants (
        p_her IN OUT NOCOPY hcfa_electronic_records%ROWTYPE
    )
    IS
    BEGIN
        IF UPPER(TRIM(p_her.sto_proc_name)) <> 'RETURN_1'
           OR p_her.sto_proc_name IS NULL THEN
            p_her.mandatory_ind := 'N';
        END IF;
    END apply_her_safety_invariants;

    PROCEDURE assert_inherited_her_safe (
        p_her IN hcfa_electronic_records%ROWTYPE
    )
    IS
    BEGIN
        IF NOT her_satisfies_safety_invariants(
            p_her.sto_proc_name, p_her.mandatory_ind
        ) THEN
            RAISE_APPLICATION_ERROR(
                c_err_unsafe_source,
                'The inherited claim configuration violates the mandatory-record rule; correct the template or billing-form source.'
            );
        END IF;
    END assert_inherited_her_safe;

    PROCEDURE resolve_pfc (
        p_payor_guid IN pfc.payor_guid%TYPE,
        p_plan_guid  IN pfc.plan_guid%TYPE,
        p_resolution OUT t_pfc_resolution
    )
    IS
        l_newest_count PLS_INTEGER := 0;
    BEGIN
        FOR candidate IN (
            SELECT
                ranked_pfc.pfc_guid,
                ranked_pfc.payor_guid,
                ranked_pfc.plan_guid,
                ranked_pfc.payor_type_guid,
                ranked_pfc.billing_form_code,
                ranked_pfc.form_template_guid,
                ranked_pfc.user_form_template_guid,
                ranked_pfc.cpd_start_date,
                ranked_pfc.cpd_end_date
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
                    DENSE_RANK() OVER (
                        ORDER BY p.cpd_start_date DESC NULLS LAST
                    ) AS start_date_rank
                FROM pfc p
                JOIN payors payor
                  ON payor.payor_guid = p.payor_guid
                WHERE p.payor_guid = p_payor_guid
                  AND p.cpd_end_date > SYSDATE
                  AND p.default_media_type = 'E'
                  AND p.type_of_bill IS NULL
                  AND (
                        (p_plan_guid IS NULL AND p.plan_guid IS NULL)
                        OR
                        (p_plan_guid IS NOT NULL AND (
                            p.plan_guid = p_plan_guid
                            OR p.plan_guid IS NULL
                        ))
                      )
            ) ranked_pfc
            WHERE ranked_pfc.start_date_rank = 1
        ) LOOP
            l_newest_count := l_newest_count + 1;

            p_resolution.pfc_guid := candidate.pfc_guid;
            p_resolution.payor_guid := candidate.payor_guid;
            p_resolution.plan_guid := candidate.plan_guid;
            p_resolution.payor_type_guid := candidate.payor_type_guid;
            p_resolution.billing_form_code := candidate.billing_form_code;
            p_resolution.form_template_guid := candidate.form_template_guid;
            p_resolution.user_form_template_guid :=
                candidate.user_form_template_guid;
            p_resolution.cpd_start_date := candidate.cpd_start_date;
            p_resolution.cpd_end_date := candidate.cpd_end_date;
        END LOOP;

        IF l_newest_count = 0 THEN
            RAISE_APPLICATION_ERROR(
                c_err_pfc_not_found,
                'No eligible PFC was found for the requested payor and plan.'
            );
        END IF;

        IF l_newest_count > 1 THEN
            RAISE_APPLICATION_ERROR(
                c_err_pfc_start_date_tie,
                'Multiple eligible PFC rows share the newest CPD start date.'
            );
        END IF;
    END resolve_pfc;
END pfc_config_internal;
/
