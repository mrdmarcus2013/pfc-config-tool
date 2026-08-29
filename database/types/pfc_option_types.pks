CREATE OR REPLACE PACKAGE pfc_option_types AUTHID DEFINER AS
    SUBTYPE t_action_code IS VARCHAR2(10);
    SUBTYPE t_option_code IS VARCHAR2(100);
    SUBTYPE t_attribute_code IS VARCHAR2(128);
    SUBTYPE t_display_label IS VARCHAR2(200);
    SUBTYPE t_phys_form_field_num IS VARCHAR2(30);
    SUBTYPE t_target_code IS VARCHAR2(30);
    SUBTYPE t_record_type_code IS VARCHAR2(20);
    SUBTYPE t_value_text IS VARCHAR2(32767);

    c_action_keep  CONSTANT t_action_code := 'KEEP';
    c_action_set   CONSTANT t_action_code := 'SET';
    c_action_clear CONSTANT t_action_code := 'CLEAR';

    c_err_invalid_option CONSTANT PLS_INTEGER := -20032;

    c_attr_field_number   CONSTANT t_attribute_code := 'FIELD_NUMBER';
    c_attr_field_name     CONSTANT t_attribute_code := 'FIELD_NAME';
    c_attr_sto_proc_name  CONSTANT t_attribute_code := 'STO_PROC_NAME';
    c_attr_hard_coded_data CONSTANT t_attribute_code := 'HARD_CODED_DATA';

    TYPE t_value_requirement IS RECORD (
        action_code t_action_code,
        value_text  t_value_text
    );

    TYPE t_selector_term IS RECORD (
        attribute_code t_attribute_code,
        expected_value t_value_text
    );

    TYPE t_selector_terms IS TABLE OF t_selector_term
        INDEX BY PLS_INTEGER;

    TYPE t_attribute_requirement IS RECORD (
        attribute_code t_attribute_code,
        desired_value  t_value_requirement
    );

    TYPE t_attribute_requirements IS TABLE OF t_attribute_requirement
        INDEX BY PLS_INTEGER;

    TYPE t_hef_requirement IS RECORD (
        selector_terms         t_selector_terms,
        attribute_requirements t_attribute_requirements
    );

    TYPE t_hef_requirements IS TABLE OF t_hef_requirement
        INDEX BY PLS_INTEGER;

    TYPE t_option_target IS RECORD (
        target_code       t_target_code,
        record_type_code  t_record_type_code,
        her_requirements  t_attribute_requirements,
        hef_requirements  t_hef_requirements
    );

    TYPE t_option_targets IS TABLE OF t_option_target
        INDEX BY PLS_INTEGER;

    TYPE t_option_definition IS RECORD (
        option_code         t_option_code,
        display_label       t_display_label,
        phys_form_field_num t_phys_form_field_num,
        targets             t_option_targets
    );

    PROCEDURE apply_hef_value_pair (
        p_sto_requirement  IN t_value_requirement,
        p_hard_requirement IN t_value_requirement,
        p_sto_proc_name    IN OUT NOCOPY t_value_text,
        p_hard_coded_data  IN OUT NOCOPY t_value_text
    );
END pfc_option_types;
/
