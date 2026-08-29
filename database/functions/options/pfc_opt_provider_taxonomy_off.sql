CREATE OR REPLACE FUNCTION pfc_opt_provider_taxonomy_off
    RETURN pfc_option_types.t_option_definition
    AUTHID DEFINER
IS
    l_option pfc_option_types.t_option_definition;
BEGIN
    l_option.option_code := 'PROVIDER_TAXONOMY_OFF';
    l_option.display_label := 'Provider Taxonomy OFF';
    l_option.phys_form_field_num := '81';

    l_option.targets(1).target_code := 'PRV';
    l_option.targets(1).record_type_code := 'B2000A0030PRV080';

    l_option.targets(1).her_requirements(1).attribute_code :=
        pfc_option_types.c_attr_sto_proc_name;
    l_option.targets(1).her_requirements(1).desired_value.action_code :=
        pfc_option_types.c_action_set;
    l_option.targets(1).her_requirements(1).desired_value.value_text :=
        'RETURN_0';

    l_option.targets(1).hef_requirements(1).selector_terms(1).attribute_code :=
        pfc_option_types.c_attr_field_name;
    l_option.targets(1).hef_requirements(1).selector_terms(1).expected_value :=
        'PRV03';

    l_option.targets(1).hef_requirements(1)
        .attribute_requirements(1).attribute_code :=
        pfc_option_types.c_attr_sto_proc_name;
    l_option.targets(1).hef_requirements(1)
        .attribute_requirements(1).desired_value.action_code :=
        pfc_option_types.c_action_set;
    l_option.targets(1).hef_requirements(1)
        .attribute_requirements(1).desired_value.value_text :=
        'G_PROVIDER_TAXONOMY_CODE';

    l_option.targets(1).hef_requirements(1)
        .attribute_requirements(2).attribute_code :=
        pfc_option_types.c_attr_hard_coded_data;
    l_option.targets(1).hef_requirements(1)
        .attribute_requirements(2).desired_value.action_code :=
        pfc_option_types.c_action_keep;
    l_option.targets(1).hef_requirements(1)
        .attribute_requirements(2).desired_value.value_text := NULL;

    RETURN l_option;
END pfc_opt_provider_taxonomy_off;
/
