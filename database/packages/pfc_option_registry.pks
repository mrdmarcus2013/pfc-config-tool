CREATE OR REPLACE PACKAGE pfc_option_registry AUTHID DEFINER AS
    c_err_unknown_option CONSTANT PLS_INTEGER := -20001;

    TYPE t_option_definitions IS TABLE OF pfc_option_types.t_option_definition
        INDEX BY PLS_INTEGER;

    TYPE t_managed_target IS RECORD (
        billing_form_code pfc_option_types.t_billing_form_code,
        record_type_code  pfc_option_types.t_record_type_code
    );
    TYPE t_managed_targets IS TABLE OF t_managed_target
        INDEX BY PLS_INTEGER;

    FUNCTION get_option (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN pfc_option_types.t_option_definition;

    PROCEDURE get_managed_targets (
        p_targets OUT t_managed_targets
    );
END pfc_option_registry;
/
