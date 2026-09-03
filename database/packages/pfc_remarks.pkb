CREATE OR REPLACE PACKAGE BODY pfc_remarks AS
    c_private_prefix CONSTANT VARCHAR2(30) := '__PFC_REMARKS_';
    c_target_code CONSTANT pfc_option_types.t_target_code := 'NTE';
    c_billing_form_code CONSTANT pfc_option_types.t_billing_form_code :=
        '837I_5010';
    c_record_type_code CONSTANT pfc_option_types.t_record_type_code :=
        'D23001900NTE182';

    g_option_code   pfc_option_types.t_option_code;
    g_mode          t_mode;
    g_custom_remark t_custom_remark;

    FUNCTION normalized_lob(p_value t_line_of_business)
        RETURN t_line_of_business
    IS
        l_value t_line_of_business := UPPER(TRIM(p_value));
    BEGIN
        IF l_value IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_lob_required,
                'A saved payor Line of Business is required for Remarks.');
        END IF;
        IF l_value NOT IN (c_home_health, c_hospice) THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_lob,
                'The saved payor Line of Business is unsupported.');
        END IF;
        RETURN l_value;
    END normalized_lob;

    PROCEDURE normalize_request(
        p_mode          IN t_mode,
        p_custom_remark IN t_custom_remark,
        p_result_mode   OUT t_mode,
        p_result_remark OUT t_custom_remark
    ) IS
    BEGIN
        p_result_mode := UPPER(TRIM(p_mode));
        p_result_remark := TRIM(p_custom_remark);
        IF p_result_mode NOT IN (c_mode_default, c_mode_custom) THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_mode,
                'Remarks mode must be DEFAULT or CUSTOM.');
        END IF;
        IF p_result_mode = c_mode_default THEN
            IF p_result_remark IS NOT NULL THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_mode,
                    'DEFAULT Remarks cannot include custom text.');
            END IF;
            RETURN;
        END IF;
        IF p_result_remark IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_custom_required,
                'Custom remark text is required.');
        END IF;
        IF LENGTH(p_result_remark) > c_custom_remark_max_length THEN
            RAISE_APPLICATION_ERROR(c_err_custom_too_long,
                'Custom remark text exceeds the configured limit.');
        END IF;
    END normalize_request;

    PROCEDURE add_managed_hef(
        p_option          IN OUT NOCOPY pfc_option_types.t_option_definition,
        p_index           IN PLS_INTEGER,
        p_field_number    IN VARCHAR2,
        p_field_name      IN VARCHAR2,
        p_sto_proc_name   IN VARCHAR2,
        p_hard_coded_data IN VARCHAR2
    ) IS
    BEGIN
        p_option.targets(1).hef_requirements(p_index)
            .selector_terms(1).attribute_code :=
                pfc_option_types.c_attr_field_number;
        p_option.targets(1).hef_requirements(p_index)
            .selector_terms(1).expected_value := p_field_number;
        p_option.targets(1).hef_requirements(p_index)
            .selector_terms(2).attribute_code :=
                pfc_option_types.c_attr_field_name;
        p_option.targets(1).hef_requirements(p_index)
            .selector_terms(2).expected_value := p_field_name;

        p_option.targets(1).hef_requirements(p_index)
            .attribute_requirements(1).attribute_code :=
                pfc_option_types.c_attr_sto_proc_name;
        p_option.targets(1).hef_requirements(p_index)
            .attribute_requirements(1).desired_value.action_code :=
                CASE WHEN p_sto_proc_name IS NULL
                    THEN pfc_option_types.c_action_clear
                    ELSE pfc_option_types.c_action_set END;
        p_option.targets(1).hef_requirements(p_index)
            .attribute_requirements(1).desired_value.value_text :=
                p_sto_proc_name;

        p_option.targets(1).hef_requirements(p_index)
            .attribute_requirements(2).attribute_code :=
                pfc_option_types.c_attr_hard_coded_data;
        p_option.targets(1).hef_requirements(p_index)
            .attribute_requirements(2).desired_value.action_code :=
                CASE WHEN p_hard_coded_data IS NULL
                    THEN pfc_option_types.c_action_clear
                    ELSE pfc_option_types.c_action_set END;
        p_option.targets(1).hef_requirements(p_index)
            .attribute_requirements(2).desired_value.value_text :=
                p_hard_coded_data;
    END add_managed_hef;

    FUNCTION prepare_private_option (
        p_line_of_business IN t_line_of_business,
        p_mode             IN t_mode,
        p_custom_remark    IN t_custom_remark
    ) RETURN pfc_option_types.t_option_code
    IS
        l_lob t_line_of_business;
    BEGIN
        l_lob := normalized_lob(p_line_of_business);
        normalize_request(p_mode, p_custom_remark, g_mode, g_custom_remark);
        g_option_code := c_private_prefix || l_lob || '_' || g_mode;
        RETURN g_option_code;
    END prepare_private_option;

    FUNCTION is_private_option_code (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN BOOLEAN
    IS
    BEGIN
        RETURN SUBSTR(UPPER(TRIM(p_option_code)), 1, LENGTH(c_private_prefix)) =
            c_private_prefix;
    END is_private_option_code;

    FUNCTION get_private_option (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN pfc_option_types.t_option_definition
    IS
        l_option pfc_option_types.t_option_definition;
        l_code pfc_option_types.t_option_code := UPPER(TRIM(p_option_code));
    BEGIN
        IF g_option_code IS NULL OR l_code <> g_option_code THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_state,
                'The private Remarks request was not prepared safely.');
        END IF;

        l_option.option_code := g_option_code;
        l_option.display_label := CASE g_mode
            WHEN c_mode_default THEN 'Default'
            ELSE 'Custom remark'
        END;
        l_option.phys_form_field_num := '80';
        l_option.inherit_source_ind :=
            CASE WHEN g_mode = c_mode_default THEN 'Y' ELSE 'N' END;
        l_option.targets(1).target_code := c_target_code;
        l_option.targets(1).billing_form_code := c_billing_form_code;
        l_option.targets(1).record_type_code := c_record_type_code;

        IF g_mode = c_mode_custom THEN
            l_option.targets(1).her_requirements(1).attribute_code :=
                pfc_option_types.c_attr_sto_proc_name;
            l_option.targets(1).her_requirements(1)
                .desired_value.action_code := pfc_option_types.c_action_set;
            l_option.targets(1).her_requirements(1)
                .desired_value.value_text := 'RETURN_1';
            add_managed_hef(l_option, 1, '00', 'NTE00', NULL, 'NTE');
            add_managed_hef(l_option, 2, '01', 'NTE01', NULL, 'ADD');
            add_managed_hef(l_option, 3, '02', 'NTE02', NULL,
                g_custom_remark);
        END IF;
        RETURN l_option;
    END get_private_option;
END pfc_remarks;
/
