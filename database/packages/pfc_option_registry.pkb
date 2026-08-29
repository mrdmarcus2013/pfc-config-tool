CREATE OR REPLACE PACKAGE BODY pfc_option_registry AS
    FUNCTION get_option (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN pfc_option_types.t_option_definition
    IS
        l_option_code pfc_option_types.t_option_code;
    BEGIN
        l_option_code := UPPER(TRIM(p_option_code));

        CASE l_option_code
            WHEN 'PROVIDER_TAXONOMY_ON' THEN
                RETURN pfc_opt_provider_taxonomy_on();
            WHEN 'PROVIDER_TAXONOMY_OFF' THEN
                RETURN pfc_opt_provider_taxonomy_off();
            WHEN 'SERVICE_FACILITY_ALWAYS_ADDRESS_YES' THEN
                RETURN pfc_opt_service_facility(l_option_code);
            WHEN 'SERVICE_FACILITY_ALWAYS_ADDRESS_NO' THEN
                RETURN pfc_opt_service_facility(l_option_code);
            WHEN 'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES' THEN
                RETURN pfc_opt_service_facility(l_option_code);
            WHEN 'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO' THEN
                RETURN pfc_opt_service_facility(l_option_code);
            WHEN 'SERVICE_FACILITY_NEVER' THEN
                RETURN pfc_opt_service_facility(l_option_code);
            ELSE
                RAISE_APPLICATION_ERROR(
                    c_err_unknown_option,
                    'Unknown PFC option code.'
                );
        END CASE;
    END get_option;
END pfc_option_registry;
/
