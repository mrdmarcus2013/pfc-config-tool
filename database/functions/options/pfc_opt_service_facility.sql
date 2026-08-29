CREATE OR REPLACE FUNCTION pfc_opt_service_facility (
    p_option_code IN pfc_option_types.t_option_code
) RETURN pfc_option_types.t_option_definition
AUTHID DEFINER
IS
    l_option pfc_option_types.t_option_definition;

    PROCEDURE set_her_value (
        p_target_index IN PLS_INTEGER,
        p_value        IN pfc_option_types.t_value_text
    )
    IS
    BEGIN
        l_option.targets(p_target_index).her_requirements(1).attribute_code :=
            pfc_option_types.c_attr_sto_proc_name;
        l_option.targets(p_target_index).her_requirements(1)
            .desired_value.action_code := pfc_option_types.c_action_set;
        l_option.targets(p_target_index).her_requirements(1)
            .desired_value.value_text := p_value;
    END set_her_value;

    PROCEDURE add_hef_requirement (
        p_target_index     IN PLS_INTEGER,
        p_requirement_index IN PLS_INTEGER,
        p_field_number     IN VARCHAR2,
        p_sto_action       IN pfc_option_types.t_action_code,
        p_sto_value        IN pfc_option_types.t_value_text,
        p_hard_action      IN pfc_option_types.t_action_code,
        p_hard_value       IN pfc_option_types.t_value_text
    )
    IS
    BEGIN
        l_option.targets(p_target_index).hef_requirements(p_requirement_index)
            .selector_terms(1).attribute_code :=
                pfc_option_types.c_attr_field_number;
        l_option.targets(p_target_index).hef_requirements(p_requirement_index)
            .selector_terms(1).expected_value := p_field_number;

        l_option.targets(p_target_index).hef_requirements(p_requirement_index)
            .attribute_requirements(1).attribute_code :=
                pfc_option_types.c_attr_sto_proc_name;
        l_option.targets(p_target_index).hef_requirements(p_requirement_index)
            .attribute_requirements(1).desired_value.action_code := p_sto_action;
        l_option.targets(p_target_index).hef_requirements(p_requirement_index)
            .attribute_requirements(1).desired_value.value_text := p_sto_value;

        l_option.targets(p_target_index).hef_requirements(p_requirement_index)
            .attribute_requirements(2).attribute_code :=
                pfc_option_types.c_attr_hard_coded_data;
        l_option.targets(p_target_index).hef_requirements(p_requirement_index)
            .attribute_requirements(2).desired_value.action_code := p_hard_action;
        l_option.targets(p_target_index).hef_requirements(p_requirement_index)
            .attribute_requirements(2).desired_value.value_text := p_hard_value;
    END add_hef_requirement;
BEGIN
    l_option.option_code := p_option_code;
    l_option.phys_form_field_num := '77';

    l_option.targets(1).target_code := 'NM1';
    l_option.targets(1).record_type_code := 'D2310E2500NM1343';
    l_option.targets(2).target_code := 'N3';
    l_option.targets(2).record_type_code := 'D2310E2650N3346';
    l_option.targets(3).target_code := 'N4';
    l_option.targets(3).record_type_code := 'D2310E2700N4347';

    CASE p_option_code
        WHEN 'SERVICE_FACILITY_ALWAYS_ADDRESS_YES' THEN
            l_option.display_label :=
                'Always report service facility; report address';
            set_her_value(1, 'RETURN_1');
            set_her_value(2, 'RETURN_1');
            set_her_value(3, 'RETURN_1');
        WHEN 'SERVICE_FACILITY_ALWAYS_ADDRESS_NO' THEN
            l_option.display_label :=
                'Always report service facility; do not report address';
            set_her_value(1, 'RETURN_1');
            set_her_value(2, 'RETURN_0');
            set_her_value(3, 'RETURN_0');
        WHEN 'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES' THEN
            l_option.display_label :=
                'Report service facility when care location is not HOME; report address';
            set_her_value(1, 'G_D2310E2500NM1343_COUNT');
            set_her_value(2, 'G_D2310E2500NM1343_COUNT');
            set_her_value(3, 'G_D2310E2500NM1343_COUNT');
        WHEN 'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO' THEN
            l_option.display_label :=
                'Report service facility when care location is not HOME; do not report address';
            set_her_value(1, 'G_D2310E2500NM1343_COUNT');
            set_her_value(2, 'RETURN_0');
            set_her_value(3, 'RETURN_0');
        WHEN 'SERVICE_FACILITY_NEVER' THEN
            l_option.display_label := 'Never report service facility';
            set_her_value(1, 'RETURN_0');
            set_her_value(2, 'RETURN_0');
            set_her_value(3, 'RETURN_0');
        ELSE
            RAISE_APPLICATION_ERROR(
                -20001,
                'Unknown PFC option code.'
            );
    END CASE;

    -- An OFF target deliberately has no managed HEF overlay.  This allows an
    -- OFF request to be source-equivalent and therefore canonical with zero
    -- payor overrides.  Active NM1 targets manage identity fields; active
    -- address targets additionally manage N3/N4 fields.
    IF p_option_code <> 'SERVICE_FACILITY_NEVER' THEN
        add_hef_requirement(
            1, 1, '01',
            pfc_option_types.c_action_keep, NULL,
            pfc_option_types.c_action_set, '77'
        );
        add_hef_requirement(
            1, 2, '02',
            pfc_option_types.c_action_keep, NULL,
            pfc_option_types.c_action_set, '2'
        );
        add_hef_requirement(
            1, 3, '03',
            pfc_option_types.c_action_set, 'G_ORGANIZATION_NAME',
            pfc_option_types.c_action_keep, NULL
        );
        add_hef_requirement(
            1, 4, '09',
            pfc_option_types.c_action_set, 'G_FACILITY_NPI',
            pfc_option_types.c_action_keep, NULL
        );
    END IF;

    IF p_option_code IN (
        'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES'
    ) THEN
        add_hef_requirement(
            2, 1, '01',
            pfc_option_types.c_action_set, 'G_CARE_LOCATION_ADDR1',
            pfc_option_types.c_action_keep, NULL
        );
        add_hef_requirement(
            2, 2, '02',
            pfc_option_types.c_action_set, 'G_CARE_LOCATION_ADDR2',
            pfc_option_types.c_action_keep, NULL
        );

        add_hef_requirement(
            3, 1, '01',
            pfc_option_types.c_action_set, 'G_CARE_LOCATION_CITY',
            pfc_option_types.c_action_keep, NULL
        );
        add_hef_requirement(
            3, 2, '02',
            pfc_option_types.c_action_set, 'G_CARE_LOCATION_STATE',
            pfc_option_types.c_action_keep, NULL
        );
        add_hef_requirement(
            3, 3, '03',
            pfc_option_types.c_action_set, 'G_CARE_LOCATION_ZIP',
            pfc_option_types.c_action_keep, NULL
        );
    END IF;

    RETURN l_option;
END pfc_opt_service_facility;
/
