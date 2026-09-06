CREATE OR REPLACE PACKAGE BODY pfc_config_internal AS

    FUNCTION owner_json(p_her_guid IN VARCHAR2, p_target IN VARCHAR2) RETURN VARCHAR2 IS
        l_json VARCHAR2(4000);
    BEGIN
        SELECT JSON_OBJECT(
            'target' VALUE p_target,
            'level' VALUE CASE WHEN payor_guid IS NOT NULL AND plan_guid IS NOT NULL THEN 'PAYOR_PLAN'
                WHEN payor_guid IS NOT NULL THEN 'PAYOR'
                WHEN user_form_template_guid IS NOT NULL THEN 'USER_TEMPLATE'
                WHEN form_template_guid IS NOT NULL THEN 'FORM_TEMPLATE'
                ELSE 'BILLING_FORM' END,
            'identifier' VALUE COALESCE(plan_guid, payor_guid, user_form_template_guid,
                form_template_guid, billing_form_code))
        INTO l_json FROM hcfa_electronic_records WHERE electronic_rec_guid = p_her_guid;
        RETURN l_json;
    END owner_json;

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
           OR TRIM(p_her.sto_proc_name) IS NULL THEN
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
                'The inherited claim configuration violates the mandatory-record rule; correct the inherited payor, template or billing-form source.'
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
        l_invalid_count PLS_INTEGER;
    BEGIN
        IF p_plan_guid IS NOT NULL THEN
            SELECT COUNT(*) INTO l_invalid_count FROM pfc_config_plans
            WHERE plan_guid = p_plan_guid AND payor_guid = p_payor_guid;
            IF l_invalid_count <> 1 THEN
                RAISE_APPLICATION_ERROR(-20010, 'Plan ownership does not match the selected payor.');
            END IF;
            SELECT COUNT(*) INTO l_invalid_count FROM pfc
            WHERE plan_guid = p_plan_guid
              AND (payor_guid <> p_payor_guid OR payor_guid IS NULL);
            IF l_invalid_count > 0 THEN
                RAISE_APPLICATION_ERROR(-20010, 'Plan ownership does not match the selected payor.');
            END IF;
        END IF;
        SELECT COUNT(*) INTO l_invalid_count FROM pfc
        WHERE payor_guid = p_payor_guid
          AND (plan_guid = p_plan_guid OR (plan_guid IS NULL AND p_plan_guid IS NULL))
          AND cpd_end_date > SYSDATE AND default_media_type = 'E'
          AND type_of_bill IS NULL AND billing_form_code = '837I_5010'
          AND rec_ent_date IS NULL;
        IF l_invalid_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20011, 'An eligible PFC is missing its entry date.');
        END IF;
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
                        ORDER BY p.rec_ent_date DESC NULLS LAST
                    ) AS start_date_rank
                FROM pfc p
                JOIN payors payor
                  ON payor.payor_guid = p.payor_guid
                WHERE p.payor_guid = p_payor_guid
                  AND p.cpd_end_date > SYSDATE
                  AND p.default_media_type = 'E'
                  AND p.type_of_bill IS NULL
                  AND p.billing_form_code = '837I_5010'
                  AND (
                        (p_plan_guid IS NULL AND p.plan_guid IS NULL)
                        OR
                        (p_plan_guid IS NOT NULL AND (
                            p.plan_guid = p_plan_guid
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
                'Multiple eligible PFC rows share the newest record entry date.'
            );
        END IF;
    END resolve_pfc;
END pfc_config_internal;
/
