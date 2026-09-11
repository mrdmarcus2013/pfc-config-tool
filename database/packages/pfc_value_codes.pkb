CREATE OR REPLACE PACKAGE BODY pfc_value_codes AS
    c_target_code CONSTANT pfc_option_types.t_target_code := 'HI';
    c_billing_form_code CONSTANT pfc_option_types.t_billing_form_code :=
        '837I_5010';
    c_record_type_code CONSTANT pfc_option_types.t_record_type_code :=
        'D23002310HI286';

    TYPE t_recipe_ids IS TABLE OF t_recipe_id INDEX BY PLS_INTEGER;

    FUNCTION values_equal(p_left VARCHAR2, p_right VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        IF p_left IS NULL THEN
            RETURN p_right IS NULL;
        ELSIF p_right IS NULL THEN
            RETURN FALSE;
        END IF;
        RETURN p_left = p_right;
    END;

    FUNCTION normalize_lob(p_line_of_business t_line_of_business)
        RETURN t_line_of_business
    IS
        l_lob t_line_of_business := UPPER(TRIM(p_line_of_business));
    BEGIN
        IF l_lob IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_lob_required,
                'A saved payor Line of Business is required for Value Codes.');
        END IF;
        IF l_lob NOT IN (c_home_health, c_hospice) THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_lob,
                'The saved payor Line of Business is unsupported.');
        END IF;
        RETURN l_lob;
    END;

    PROCEDURE validate_flag(p_name VARCHAR2, p_value t_flag) IS
    BEGIN
        IF p_value IS NULL OR UPPER(TRIM(p_value)) NOT IN ('Y', 'N') THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_selection,
                p_name || ' must be Y or N.');
        END IF;
    END;

    FUNCTION normalized_selections(p_selections t_selections)
        RETURN t_selections
    IS
        l_selections t_selections := p_selections;
    BEGIN
        validate_flag('CBSA', l_selections.cbsa);
        validate_flag('FIPS', l_selections.fips);
        validate_flag('Care-location value code',
            l_selections.care_location_value_code);
        validate_flag('Patient-entered value code',
            l_selections.patient_entered_value_code);
        validate_flag('Covered-days value code',
            l_selections.covered_days_value_code);
        l_selections.cbsa := UPPER(TRIM(l_selections.cbsa));
        l_selections.fips := UPPER(TRIM(l_selections.fips));
        l_selections.care_location_value_code :=
            UPPER(TRIM(l_selections.care_location_value_code));
        l_selections.patient_entered_value_code :=
            UPPER(TRIM(l_selections.patient_entered_value_code));
        l_selections.covered_days_value_code :=
            UPPER(TRIM(l_selections.covered_days_value_code));
        RETURN l_selections;
    END;

    FUNCTION recipe_id_for (
        p_line_of_business t_line_of_business,
        p_selections       t_selections,
        p_empty_selection_behavior VARCHAR2 DEFAULT 'INHERIT'
    ) RETURN t_recipe_id
    IS
        l_lob t_line_of_business := normalize_lob(p_line_of_business);
        l_selections t_selections := normalized_selections(p_selections);
        l_key VARCHAR2(5);
        l_empty_behavior VARCHAR2(32767) := UPPER(TRIM(p_empty_selection_behavior));
    BEGIN
        IF l_empty_behavior IS NULL OR l_empty_behavior NOT IN ('INHERIT', 'OFF') THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_selection,
                'Empty Value Codes selection behavior must be INHERIT or OFF.');
        END IF;
        IF l_lob = c_home_health THEN
            IF l_selections.care_location_value_code = 'Y'
               OR l_selections.patient_entered_value_code = 'Y'
               OR l_selections.covered_days_value_code = 'Y' THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_selection,
                    'Home Health cannot use Hospice Value Codes capabilities.');
            END IF;
            IF l_selections.fips = 'Y' AND l_selections.cbsa = 'N' THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_selection,
                    'Add FIPS requires Add CBSA.');
            END IF;
            IF l_selections.cbsa = 'N' THEN
                RETURN CASE WHEN l_empty_behavior = 'OFF'
                    THEN c_recipe_home_health_neutral ELSE c_recipe_default END;
            ELSIF l_selections.fips = 'N' THEN
                RETURN c_recipe_home_health_cbsa;
            END IF;
            RETURN c_recipe_home_health_cbsa_fips;
        END IF;

        IF l_selections.cbsa = 'Y' OR l_selections.fips = 'Y' THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_selection,
                'Hospice cannot use Home Health Value Codes capabilities.');
        END IF;
        l_key := l_selections.care_location_value_code ||
            l_selections.patient_entered_value_code ||
            l_selections.covered_days_value_code;
        CASE l_key
            WHEN 'NNN' THEN RETURN CASE WHEN l_empty_behavior = 'OFF'
                THEN c_recipe_hospice_off ELSE c_recipe_default END;
            WHEN 'YNN' THEN RETURN c_recipe_hospice_61_g8;
            WHEN 'YNY' THEN RETURN c_recipe_hospice_61_g8_vc80;
            WHEN 'NYN' THEN RETURN c_recipe_hospice_patient;
            WHEN 'NYY' THEN RETURN c_recipe_hospice_patient_vc80;
            WHEN 'NNY' THEN RETURN c_recipe_hospice_vc80;
            ELSE
                RAISE_APPLICATION_ERROR(c_err_invalid_selection,
                    'The requested Hospice Value Codes combination is not registered.');
        END CASE;
    END;

    PROCEDURE add_hef_requirement (
        p_option            IN OUT NOCOPY pfc_option_types.t_option_definition,
        p_index             PLS_INTEGER,
        p_field_number      VARCHAR2,
        p_sto_proc_name     VARCHAR2,
        p_hard_coded_data   VARCHAR2
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
            .selector_terms(2).expected_value := 'HI' || p_field_number;

        p_option.targets(1).hef_requirements(p_index)
            .attribute_requirements(1).attribute_code :=
                pfc_option_types.c_attr_sto_proc_name;
        p_option.targets(1).hef_requirements(p_index)
            .attribute_requirements(1).desired_value.action_code :=
                CASE WHEN p_sto_proc_name IS NULL
                    THEN pfc_option_types.c_action_clear
                    ELSE pfc_option_types.c_action_set END;
        p_option.targets(1).hef_requirements(p_index)
            .attribute_requirements(1).desired_value.value_text := p_sto_proc_name;

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
    END;

    FUNCTION recipe_definition(
        p_recipe_id   t_recipe_id,
        p_option_code pfc_option_types.t_option_code DEFAULT NULL
    )
        RETURN pfc_option_types.t_option_definition
    IS
        l_option pfc_option_types.t_option_definition;
    BEGIN
        l_option.option_code := NVL(p_option_code, p_recipe_id);
        l_option.display_label := CASE p_recipe_id
            WHEN c_recipe_default THEN 'Default'
            WHEN c_recipe_home_health_neutral THEN 'CBSA and FIPS off'
            WHEN c_recipe_hospice_off THEN 'Value Codes off'
            WHEN c_recipe_home_health_cbsa THEN 'CBSA'
            WHEN c_recipe_home_health_cbsa_fips THEN 'CBSA and FIPS'
            WHEN c_recipe_hospice_61_g8 THEN 'Care-location value code 61/G8'
            WHEN c_recipe_hospice_61_g8_vc80 THEN
                'Care-location value code 61/G8 and value code 80 with days covered'
            WHEN c_recipe_hospice_patient THEN
                'Patient-entered value code and amount'
            WHEN c_recipe_hospice_patient_vc80 THEN
                'Patient-entered value code and amount and value code 80 with days covered'
            WHEN c_recipe_hospice_vc80 THEN 'Value code 80 with days covered'
        END;
        l_option.phys_form_field_num := '39-41';
        l_option.inherit_source_ind :=
            CASE WHEN p_recipe_id = c_recipe_default THEN 'Y' ELSE 'N' END;
        l_option.targets(1).target_code := c_target_code;
        l_option.targets(1).billing_form_code := c_billing_form_code;
        l_option.targets(1).record_type_code := c_record_type_code;
        -- HH neutral removes only CBSA/FIPS substitutions; retain the source HER gate.
        IF p_recipe_id NOT IN (c_recipe_default, c_recipe_home_health_neutral) THEN
            l_option.targets(1).her_requirements(1).attribute_code :=
                pfc_option_types.c_attr_sto_proc_name;
            l_option.targets(1).her_requirements(1).desired_value.action_code :=
                pfc_option_types.c_action_set;
            l_option.targets(1).her_requirements(1).desired_value.value_text :=
                CASE WHEN p_recipe_id = c_recipe_hospice_off THEN 'RETURN_0' ELSE 'RETURN_1' END;
        END IF;

        CASE p_recipe_id
            WHEN c_recipe_default THEN NULL;
            WHEN c_recipe_home_health_neutral THEN
                add_hef_requirement(l_option, 1, '012', 'GET_VAL_CODE', NULL);
                add_hef_requirement(l_option, 2, '015', 'GET_VAL_CODE_AMT', NULL);
                add_hef_requirement(l_option, 3, '022', 'GET_VAL_CODE', NULL);
                add_hef_requirement(l_option, 4, '025', 'GET_VAL_CODE_AMT', NULL);
            WHEN c_recipe_hospice_off THEN NULL;
            WHEN c_recipe_home_health_cbsa THEN
                add_hef_requirement(l_option, 1, '012', NULL, '61');
                add_hef_requirement(l_option, 2, '015', 'GET_PAT_CBSA_CODE', NULL);
                add_hef_requirement(l_option, 3, '022', 'GET_VAL_CODE', NULL);
                add_hef_requirement(l_option, 4, '025', 'GET_VAL_CODE_AMT', NULL);
            WHEN c_recipe_home_health_cbsa_fips THEN
                add_hef_requirement(l_option, 1, '012', NULL, '61');
                add_hef_requirement(l_option, 2, '015', 'GET_PAT_CBSA_CODE', NULL);
                add_hef_requirement(l_option, 3, '022', 'GET_FIPS_CODE', NULL);
                add_hef_requirement(l_option, 4, '025', 'GET_FIPS_CODE_VALUE', NULL);
            WHEN c_recipe_hospice_61_g8 THEN
                add_hef_requirement(l_option, 1, '012', 'GET_CARE_LOC_CODE', NULL);
                add_hef_requirement(l_option, 2, '015', 'GET_CARE_LOC_VAL_CODE', NULL);
                add_hef_requirement(l_option, 3, '022', 'GET_VAL_CODE', NULL);
                add_hef_requirement(l_option, 4, '025', 'GET_VAL_CODE_AMT', NULL);
            WHEN c_recipe_hospice_61_g8_vc80 THEN
                add_hef_requirement(l_option, 1, '012', 'GET_CARE_LOC_CODE', NULL);
                add_hef_requirement(l_option, 2, '015', 'GET_CARE_LOC_VAL_CODE', NULL);
                add_hef_requirement(l_option, 3, '022', NULL, '80');
                add_hef_requirement(l_option, 4, '025', 'GET_DISTINCT_COVERED_DAYS', NULL);
            WHEN c_recipe_hospice_patient THEN
                add_hef_requirement(l_option, 1, '012', 'GET_VAL_CODE', NULL);
                add_hef_requirement(l_option, 2, '015', 'GET_VAL_CODE_AMT', NULL);
                add_hef_requirement(l_option, 3, '022', 'GET_VAL_CODE', NULL);
                add_hef_requirement(l_option, 4, '025', 'GET_VAL_CODE_AMT', NULL);
            WHEN c_recipe_hospice_patient_vc80 THEN
                add_hef_requirement(l_option, 1, '012', 'GET_VAL_CODE', NULL);
                add_hef_requirement(l_option, 2, '015', 'GET_VAL_CODE_AMT', NULL);
                add_hef_requirement(l_option, 3, '022', NULL, '80');
                add_hef_requirement(l_option, 4, '025', 'GET_DISTINCT_COVERED_DAYS', NULL);
            WHEN c_recipe_hospice_vc80 THEN
                add_hef_requirement(l_option, 1, '012', NULL, '80');
                add_hef_requirement(l_option, 2, '015', 'GET_DISTINCT_COVERED_DAYS', NULL);
                add_hef_requirement(l_option, 3, '022', 'GET_VAL_CODE', NULL);
                add_hef_requirement(l_option, 4, '025', 'GET_VAL_CODE_AMT', NULL);
            ELSE
                RAISE_APPLICATION_ERROR(c_err_invalid_selection,
                    'The Value Codes recipe is not registered.');
        END CASE;
        RETURN l_option;
    END;

    FUNCTION no_selections RETURN t_selections IS
        l_selections t_selections;
    BEGIN
        l_selections.cbsa := 'N';
        l_selections.fips := 'N';
        l_selections.care_location_value_code := 'N';
        l_selections.patient_entered_value_code := 'N';
        l_selections.covered_days_value_code := 'N';
        RETURN l_selections;
    END;

    FUNCTION private_option_code (
        p_line_of_business IN t_line_of_business,
        p_selections       IN t_selections,
        p_empty_selection_behavior IN VARCHAR2 DEFAULT 'INHERIT'
    ) RETURN pfc_option_types.t_option_code
    IS
        l_lob t_line_of_business := normalize_lob(p_line_of_business);
        l_selections t_selections := normalized_selections(p_selections);
        l_recipe_id t_recipe_id;
    BEGIN
        /* Validation is deliberately shared with recipe selection. */
        l_recipe_id := recipe_id_for(l_lob, l_selections, p_empty_selection_behavior);
        RETURN 'VC|' || l_lob || '|' || l_selections.cbsa || '|' ||
            l_selections.fips || '|' ||
            l_selections.care_location_value_code || '|' ||
            l_selections.patient_entered_value_code || '|' ||
            l_selections.covered_days_value_code ||
            CASE WHEN l_recipe_id IN (c_recipe_home_health_neutral, c_recipe_hospice_off)
                THEN '|OFF' END;
    END;

    FUNCTION is_private_option_code (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN BOOLEAN
    IS
    BEGIN
        RETURN UPPER(TRIM(p_option_code)) LIKE 'VC|%';
    END;

    FUNCTION get_private_option (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN pfc_option_types.t_option_definition
    IS
        l_code pfc_option_types.t_option_code := UPPER(TRIM(p_option_code));
        l_selections t_selections;
        l_recipe_id t_recipe_id;

        FUNCTION candidate_matches(p_lob t_line_of_business) RETURN BOOLEAN IS
        BEGIN
            IF private_option_code(p_lob, l_selections) = l_code THEN
                l_recipe_id := recipe_id_for(p_lob, l_selections);
                RETURN TRUE;
            END IF;
            RETURN FALSE;
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = c_err_invalid_selection THEN RETURN FALSE; END IF;
                RAISE;
        END;
    BEGIN
        IF NOT is_private_option_code(l_code) THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_selection,
                'The private Value Codes selection is invalid.');
        END IF;

        l_selections := no_selections;
        IF private_option_code(c_home_health, l_selections, 'OFF') = l_code THEN
            RETURN recipe_definition(c_recipe_home_health_neutral, l_code);
        ELSIF private_option_code(c_hospice, l_selections, 'OFF') = l_code THEN
            RETURN recipe_definition(c_recipe_hospice_off, l_code);
        END IF;

        FOR l_mask IN 0 .. 31 LOOP
            l_selections.cbsa := CASE WHEN BITAND(l_mask, 1) <> 0 THEN 'Y' ELSE 'N' END;
            l_selections.fips := CASE WHEN BITAND(l_mask, 2) <> 0 THEN 'Y' ELSE 'N' END;
            l_selections.care_location_value_code :=
                CASE WHEN BITAND(l_mask, 4) <> 0 THEN 'Y' ELSE 'N' END;
            l_selections.patient_entered_value_code :=
                CASE WHEN BITAND(l_mask, 8) <> 0 THEN 'Y' ELSE 'N' END;
            l_selections.covered_days_value_code :=
                CASE WHEN BITAND(l_mask, 16) <> 0 THEN 'Y' ELSE 'N' END;
            IF candidate_matches(c_home_health) OR candidate_matches(c_hospice) THEN
                RETURN recipe_definition(l_recipe_id, l_code);
            END IF;
        END LOOP;
        RAISE_APPLICATION_ERROR(c_err_invalid_selection,
            'The private Value Codes selection is invalid.');
    END;

    FUNCTION get_recipe (
        p_line_of_business IN t_line_of_business,
        p_selections       IN t_selections,
        p_empty_selection_behavior IN VARCHAR2 DEFAULT 'INHERIT'
    ) RETURN pfc_option_types.t_option_definition
    IS
    BEGIN
        RETURN recipe_definition(recipe_id_for(p_line_of_business, p_selections, p_empty_selection_behavior));
    END;

    FUNCTION build_desired_state (
        p_line_of_business IN t_line_of_business,
        p_selections       IN t_selections,
        p_source_state     IN t_configuration_state,
        p_empty_selection_behavior IN VARCHAR2 DEFAULT 'INHERIT'
    ) RETURN t_configuration_state
    IS
        l_option pfc_option_types.t_option_definition :=
            get_recipe(p_line_of_business, p_selections, p_empty_selection_behavior);
        l_desired t_configuration_state := p_source_state;
        l_requirement_index PLS_INTEGER;
        l_attribute_index PLS_INTEGER;
        l_hef_index PLS_INTEGER;
        l_match_index PLS_INTEGER;
        l_match_count PLS_INTEGER;
        l_sto_requirement pfc_option_types.t_value_requirement;
        l_hard_requirement pfc_option_types.t_value_requirement;
        l_sto_value pfc_option_types.t_value_text;
        l_hard_value pfc_option_types.t_value_text;
    BEGIN
        IF l_option.targets(1).her_requirements.COUNT > 0 THEN
            l_desired.her_sto_proc_name := l_option.targets(1)
                .her_requirements(1).desired_value.value_text;
        END IF;
        l_requirement_index := l_option.targets(1).hef_requirements.FIRST;
        WHILE l_requirement_index IS NOT NULL LOOP
            l_match_index := NULL;
            l_match_count := 0;
            l_hef_index := l_desired.hefs.FIRST;
            WHILE l_hef_index IS NOT NULL LOOP
                IF l_desired.hefs(l_hef_index).field_number =
                   l_option.targets(1).hef_requirements(l_requirement_index)
                       .selector_terms(1).expected_value THEN
                    l_match_index := l_hef_index;
                    l_match_count := l_match_count + 1;
                END IF;
                l_hef_index := l_desired.hefs.NEXT(l_hef_index);
            END LOOP;
            IF l_match_count <> 1 THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_state,
                    'Each managed Value Codes HEF must exist exactly once.');
            END IF;

            l_sto_requirement.action_code := pfc_option_types.c_action_keep;
            l_sto_requirement.value_text := NULL;
            l_hard_requirement.action_code := pfc_option_types.c_action_keep;
            l_hard_requirement.value_text := NULL;
            l_attribute_index := l_option.targets(1)
                .hef_requirements(l_requirement_index)
                .attribute_requirements.FIRST;
            WHILE l_attribute_index IS NOT NULL LOOP
                IF l_option.targets(1).hef_requirements(l_requirement_index)
                    .attribute_requirements(l_attribute_index).attribute_code =
                    pfc_option_types.c_attr_sto_proc_name THEN
                    l_sto_requirement := l_option.targets(1)
                        .hef_requirements(l_requirement_index)
                        .attribute_requirements(l_attribute_index).desired_value;
                ELSIF l_option.targets(1).hef_requirements(l_requirement_index)
                    .attribute_requirements(l_attribute_index).attribute_code =
                    pfc_option_types.c_attr_hard_coded_data THEN
                    l_hard_requirement := l_option.targets(1)
                        .hef_requirements(l_requirement_index)
                        .attribute_requirements(l_attribute_index).desired_value;
                ELSE
                    RAISE_APPLICATION_ERROR(c_err_invalid_state,
                        'A Value Codes recipe contains an unsupported HEF attribute.');
                END IF;
                l_attribute_index := l_option.targets(1)
                    .hef_requirements(l_requirement_index)
                    .attribute_requirements.NEXT(l_attribute_index);
            END LOOP;
            l_sto_value := l_desired.hefs(l_match_index).sto_proc_name;
            l_hard_value := l_desired.hefs(l_match_index).hard_coded_data;
            pfc_option_types.apply_hef_value_pair(
                l_sto_requirement, l_hard_requirement,
                l_sto_value, l_hard_value);
            l_desired.hefs(l_match_index).sto_proc_name := l_sto_value;
            l_desired.hefs(l_match_index).hard_coded_data := l_hard_value;
            l_requirement_index := l_option.targets(1).hef_requirements.NEXT(
                l_requirement_index);
        END LOOP;
        RETURN l_desired;
    END;

    FUNCTION recipe_matches (
        p_recipe_id t_recipe_id,
        p_state     t_configuration_state
    ) RETURN BOOLEAN
    IS
        l_option pfc_option_types.t_option_definition :=
            recipe_definition(p_recipe_id);
        l_requirement_index PLS_INTEGER;
        l_hef_index PLS_INTEGER;
        l_match_count PLS_INTEGER;
        l_expected_sto VARCHAR2(32767);
        l_expected_hard VARCHAR2(32767);
    BEGIN
        IF p_recipe_id = c_recipe_default THEN
            RETURN FALSE;
        END IF;
        IF p_recipe_id = c_recipe_home_health_neutral THEN
            -- Unknown inherited gating is not enough evidence to classify its capabilities.
            IF p_state.her_sto_proc_name IS NULL
               OR p_state.her_sto_proc_name NOT IN ('RETURN_1', 'RETURN_0') THEN
                RETURN FALSE;
            END IF;
        ELSIF NOT values_equal(p_state.her_sto_proc_name,
            l_option.targets(1).her_requirements(1).desired_value.value_text) THEN
            RETURN FALSE;
        END IF;
        l_requirement_index := l_option.targets(1).hef_requirements.FIRST;
        WHILE l_requirement_index IS NOT NULL LOOP
            l_expected_sto := l_option.targets(1)
                .hef_requirements(l_requirement_index)
                .attribute_requirements(1).desired_value.value_text;
            l_expected_hard := l_option.targets(1)
                .hef_requirements(l_requirement_index)
                .attribute_requirements(2).desired_value.value_text;
            l_match_count := 0;
            l_hef_index := p_state.hefs.FIRST;
            WHILE l_hef_index IS NOT NULL LOOP
                IF p_state.hefs(l_hef_index).field_number =
                   l_option.targets(1).hef_requirements(l_requirement_index)
                       .selector_terms(1).expected_value THEN
                    l_match_count := l_match_count + 1;
                    IF NOT values_equal(p_state.hefs(l_hef_index).sto_proc_name,
                                        l_expected_sto)
                       OR NOT values_equal(p_state.hefs(l_hef_index).hard_coded_data,
                                           l_expected_hard)
                       OR (p_recipe_id = c_recipe_home_health_neutral
                           AND NOT values_equal(p_state.hefs(l_hef_index).field_name,
                               'HI' || p_state.hefs(l_hef_index).field_number))
                       OR (p_state.hefs(l_hef_index).sto_proc_name IS NOT NULL
                           AND p_state.hefs(l_hef_index).hard_coded_data IS NOT NULL) THEN
                        RETURN FALSE;
                    END IF;
                END IF;
                l_hef_index := p_state.hefs.NEXT(l_hef_index);
            END LOOP;
            IF l_match_count <> 1 THEN RETURN FALSE; END IF;
            l_requirement_index := l_option.targets(1).hef_requirements.NEXT(
                l_requirement_index);
        END LOOP;
        RETURN TRUE;
    END;

    FUNCTION recognize_state (
        p_line_of_business IN t_line_of_business,
        p_effective_state  IN t_configuration_state
    ) RETURN t_recipe_id
    IS
        l_lob t_line_of_business := normalize_lob(p_line_of_business);
        l_ids t_recipe_ids;
        l_match_count PLS_INTEGER := 0;
        l_match t_recipe_id;
    BEGIN
        IF l_lob = c_home_health THEN
            l_ids(1) := c_recipe_home_health_cbsa;
            l_ids(2) := c_recipe_home_health_cbsa_fips;
            l_ids(3) := c_recipe_home_health_neutral;
        ELSE
            l_ids(1) := c_recipe_hospice_61_g8;
            l_ids(2) := c_recipe_hospice_61_g8_vc80;
            l_ids(3) := c_recipe_hospice_patient;
            l_ids(4) := c_recipe_hospice_patient_vc80;
            l_ids(5) := c_recipe_hospice_vc80;
            l_ids(6) := c_recipe_hospice_off;
        END IF;
        FOR i IN 1 .. l_ids.COUNT LOOP
            IF recipe_matches(l_ids(i), p_effective_state) THEN
                l_match_count := l_match_count + 1;
                l_match := l_ids(i);
            END IF;
        END LOOP;
        IF l_match_count = 0 THEN RETURN c_recipe_unrecognized; END IF;
        IF l_match_count > 1 THEN RETURN c_recipe_ambiguous; END IF;
        RETURN l_match;
    END;

    FUNCTION configurations_equal (
        p_left  t_configuration_state,
        p_right t_configuration_state
    ) RETURN BOOLEAN
    IS
        l_left_index PLS_INTEGER;
        l_right_index PLS_INTEGER;
        l_match_count PLS_INTEGER;
    BEGIN
        IF NOT values_equal(p_left.her_sto_proc_name,
                            p_right.her_sto_proc_name)
           OR p_left.hefs.COUNT <> p_right.hefs.COUNT THEN
            RETURN FALSE;
        END IF;
        l_left_index := p_left.hefs.FIRST;
        WHILE l_left_index IS NOT NULL LOOP
            l_match_count := 0;
            l_right_index := p_right.hefs.FIRST;
            WHILE l_right_index IS NOT NULL LOOP
                IF values_equal(p_left.hefs(l_left_index).field_number,
                                p_right.hefs(l_right_index).field_number)
                   AND values_equal(p_left.hefs(l_left_index).field_name,
                                    p_right.hefs(l_right_index).field_name)
                   AND values_equal(p_left.hefs(l_left_index).sto_proc_name,
                                    p_right.hefs(l_right_index).sto_proc_name)
                   AND values_equal(p_left.hefs(l_left_index).hard_coded_data,
                                    p_right.hefs(l_right_index).hard_coded_data) THEN
                    l_match_count := l_match_count + 1;
                END IF;
                l_right_index := p_right.hefs.NEXT(l_right_index);
            END LOOP;
            IF l_match_count <> 1 THEN RETURN FALSE; END IF;
            l_left_index := p_left.hefs.NEXT(l_left_index);
        END LOOP;
        RETURN TRUE;
    END;

    FUNCTION canonical_override_count (
        p_source_state  IN t_configuration_state,
        p_desired_state IN t_configuration_state
    ) RETURN PLS_INTEGER
    IS
    BEGIN
        IF configurations_equal(p_source_state, p_desired_state) THEN
            RETURN 0;
        END IF;
        RETURN 1;
    END;

    FUNCTION current_effective_status (
        p_source_status             IN VARCHAR2,
        p_existing_payor_her_count IN PLS_INTEGER,
        p_recognized_recipe         IN t_recipe_id
    ) RETURN VARCHAR2
    IS
    BEGIN
        IF UPPER(TRIM(p_source_status)) <> 'RESOLVED' THEN
            RETURN 'BLOCKED_SOURCE';
        END IF;
        IF p_existing_payor_her_count IS NULL
           OR p_existing_payor_her_count < 0 THEN
            RETURN 'BLOCKED_INVALID_COUNT';
        END IF;
        IF p_existing_payor_her_count > 1 THEN
            RETURN 'BLOCKED_DUPLICATE_PAYOR_HER';
        END IF;
        IF p_recognized_recipe = c_recipe_ambiguous THEN
            RETURN c_recipe_ambiguous;
        END IF;
        IF p_recognized_recipe = c_recipe_unrecognized
           OR p_recognized_recipe IS NULL THEN
            RETURN c_recipe_unrecognized;
        END IF;
        RETURN 'RESOLVED';
    END;
END pfc_value_codes;
/
