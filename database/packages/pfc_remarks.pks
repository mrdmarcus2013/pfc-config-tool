CREATE OR REPLACE PACKAGE pfc_remarks AUTHID DEFINER AS
    SUBTYPE t_line_of_business IS VARCHAR2(20);
    SUBTYPE t_mode IS VARCHAR2(10);
    SUBTYPE t_custom_remark IS hcfa_electronic_fields.hard_coded_data%TYPE;

    c_home_health CONSTANT t_line_of_business := 'HOME_HEALTH';
    c_hospice     CONSTANT t_line_of_business := 'HOSPICE';
    c_mode_default CONSTANT t_mode := 'DEFAULT';
    c_mode_custom  CONSTANT t_mode := 'CUSTOM';

    /* Temporary business-configured limit; change this named constant only. */
    c_custom_remark_max_length CONSTANT PLS_INTEGER := 100;

    c_err_lob_required         CONSTANT PLS_INTEGER := -20070;
    c_err_invalid_lob          CONSTANT PLS_INTEGER := -20071;
    c_err_invalid_mode         CONSTANT PLS_INTEGER := -20072;
    c_err_custom_required      CONSTANT PLS_INTEGER := -20073;
    c_err_custom_too_long      CONSTANT PLS_INTEGER := -20074;
    c_err_invalid_state        CONSTANT PLS_INTEGER := -20075;

    FUNCTION prepare_private_option (
        p_line_of_business IN t_line_of_business,
        p_mode             IN t_mode,
        p_custom_remark    IN t_custom_remark
    ) RETURN pfc_option_types.t_option_code;

    FUNCTION is_private_option_code (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN BOOLEAN;

    FUNCTION get_private_option (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN pfc_option_types.t_option_definition;
END pfc_remarks;
/
