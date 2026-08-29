CREATE OR REPLACE PACKAGE BODY pfc_option_types AS
    PROCEDURE validate_requirement (
        p_requirement IN t_value_requirement
    )
    IS
        l_action t_action_code := UPPER(TRIM(p_requirement.action_code));
    BEGIN
        IF l_action IS NULL OR l_action NOT IN (
            c_action_keep,
            c_action_set,
            c_action_clear
        ) THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'A HEF value mechanism contains an invalid action.');
        END IF;
        IF l_action = c_action_set
           AND p_requirement.value_text IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'A HEF SET action must provide a non-null value.');
        END IF;
        IF l_action IN (c_action_keep, c_action_clear)
           AND p_requirement.value_text IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'HEF KEEP and CLEAR actions cannot provide a value.');
        END IF;
    END validate_requirement;

    PROCEDURE apply_hef_value_pair (
        p_sto_requirement  IN t_value_requirement,
        p_hard_requirement IN t_value_requirement,
        p_sto_proc_name    IN OUT NOCOPY t_value_text,
        p_hard_coded_data  IN OUT NOCOPY t_value_text
    )
    IS
        l_sto_action  t_action_code :=
            UPPER(TRIM(p_sto_requirement.action_code));
        l_hard_action t_action_code :=
            UPPER(TRIM(p_hard_requirement.action_code));
    BEGIN
        validate_requirement(p_sto_requirement);
        validate_requirement(p_hard_requirement);

        IF l_sto_action = c_action_set
           AND p_sto_requirement.value_text IS NOT NULL
           AND l_hard_action = c_action_set
           AND p_hard_requirement.value_text IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'A managed HEF cannot SET STO_PROC_NAME and ' ||
                'HARD_CODED_DATA to non-null values together.');
        END IF;

        IF l_sto_action = c_action_set THEN
            p_sto_proc_name := p_sto_requirement.value_text;
        ELSIF l_sto_action = c_action_clear THEN
            p_sto_proc_name := NULL;
        END IF;

        IF l_hard_action = c_action_set THEN
            p_hard_coded_data := p_hard_requirement.value_text;
        ELSIF l_hard_action = c_action_clear THEN
            p_hard_coded_data := NULL;
        END IF;

        IF l_sto_action = c_action_set
           AND p_sto_requirement.value_text IS NOT NULL THEN
            p_hard_coded_data := NULL;
        ELSIF l_hard_action = c_action_set
              AND p_hard_requirement.value_text IS NOT NULL THEN
            p_sto_proc_name := NULL;
        END IF;
    END apply_hef_value_pair;
END pfc_option_types;
/
