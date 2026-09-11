CREATE OR REPLACE PACKAGE pfc_value_codes AUTHID DEFINER AS
    SUBTYPE t_flag IS VARCHAR2(1);
    SUBTYPE t_line_of_business IS VARCHAR2(20);
    SUBTYPE t_recipe_id IS VARCHAR2(50);

    c_home_health CONSTANT t_line_of_business := 'HOME_HEALTH';
    c_hospice     CONSTANT t_line_of_business := 'HOSPICE';

    c_recipe_default CONSTANT t_recipe_id := 'DEFAULT';
    c_recipe_home_health_neutral CONSTANT t_recipe_id := 'HOME_HEALTH_NO_CBSA_FIPS';
    c_recipe_hospice_off CONSTANT t_recipe_id := 'HOSPICE_OFF';
    c_recipe_home_health_cbsa CONSTANT t_recipe_id := 'HOME_HEALTH_CBSA';
    c_recipe_home_health_cbsa_fips CONSTANT t_recipe_id :=
        'HOME_HEALTH_CBSA_FIPS';
    c_recipe_hospice_61_g8 CONSTANT t_recipe_id := 'HOSPICE_61_G8';
    c_recipe_hospice_61_g8_vc80 CONSTANT t_recipe_id :=
        'HOSPICE_61_G8_VC80_DAYS';
    c_recipe_hospice_patient CONSTANT t_recipe_id :=
        'HOSPICE_PATIENT_VALUE';
    c_recipe_hospice_patient_vc80 CONSTANT t_recipe_id :=
        'HOSPICE_PATIENT_VALUE_VC80_DAYS';
    c_recipe_hospice_vc80 CONSTANT t_recipe_id := 'HOSPICE_VC80_DAYS';
    c_recipe_unrecognized CONSTANT t_recipe_id := 'UNRECOGNIZED';
    c_recipe_ambiguous CONSTANT t_recipe_id := 'AMBIGUOUS';

    c_err_lob_required      CONSTANT PLS_INTEGER := -20060;
    c_err_invalid_lob       CONSTANT PLS_INTEGER := -20061;
    c_err_invalid_selection CONSTANT PLS_INTEGER := -20062;
    c_err_invalid_state     CONSTANT PLS_INTEGER := -20063;

    TYPE t_selections IS RECORD (
        cbsa                        t_flag,
        fips                        t_flag,
        care_location_value_code    t_flag,
        patient_entered_value_code  t_flag,
        covered_days_value_code     t_flag
    );

    TYPE t_hef_state IS RECORD (
        field_number    hcfa_electronic_fields.field_number%TYPE,
        field_name      hcfa_electronic_fields.field_name%TYPE,
        sto_proc_name   hcfa_electronic_fields.sto_proc_name%TYPE,
        hard_coded_data hcfa_electronic_fields.hard_coded_data%TYPE
    );
    TYPE t_hef_states IS TABLE OF t_hef_state INDEX BY PLS_INTEGER;

    TYPE t_configuration_state IS RECORD (
        her_sto_proc_name hcfa_electronic_records.sto_proc_name%TYPE,
        hefs               t_hef_states
    );

    FUNCTION no_selections RETURN t_selections;

    FUNCTION private_option_code (
        p_line_of_business IN t_line_of_business,
        p_selections       IN t_selections,
        p_empty_selection_behavior IN VARCHAR2 DEFAULT 'INHERIT'
    ) RETURN pfc_option_types.t_option_code;

    FUNCTION is_private_option_code (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN BOOLEAN;

    FUNCTION get_private_option (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN pfc_option_types.t_option_definition;

    FUNCTION get_recipe (
        p_line_of_business IN t_line_of_business,
        p_selections       IN t_selections,
        p_empty_selection_behavior IN VARCHAR2 DEFAULT 'INHERIT'
    ) RETURN pfc_option_types.t_option_definition;

    FUNCTION build_desired_state (
        p_line_of_business IN t_line_of_business,
        p_selections       IN t_selections,
        p_source_state     IN t_configuration_state,
        p_empty_selection_behavior IN VARCHAR2 DEFAULT 'INHERIT'
    ) RETURN t_configuration_state;

    FUNCTION recognize_state (
        p_line_of_business IN t_line_of_business,
        p_effective_state  IN t_configuration_state
    ) RETURN t_recipe_id;

    FUNCTION canonical_override_count (
        p_source_state  IN t_configuration_state,
        p_desired_state IN t_configuration_state
    ) RETURN PLS_INTEGER;

    FUNCTION current_effective_status (
        p_source_status             IN VARCHAR2,
        p_existing_payor_her_count IN PLS_INTEGER,
        p_recognized_recipe         IN t_recipe_id
    ) RETURN VARCHAR2;
END pfc_value_codes;
/
