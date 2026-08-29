CREATE OR REPLACE PACKAGE pfc_option_registry AUTHID DEFINER AS
    c_err_unknown_option CONSTANT PLS_INTEGER := -20001;

    FUNCTION get_option (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN pfc_option_types.t_option_definition;
END pfc_option_registry;
/
