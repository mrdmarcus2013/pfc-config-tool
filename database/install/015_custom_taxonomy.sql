WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON
PROMPT Installing custom taxonomy without reseeding configuration
@@../functions/options/pfc_opt_provider_taxonomy_on.sql
ALTER PACKAGE pfc_option_registry COMPILE BODY;
@@../procedures/03_pfc_apply_option.sql
@@../procedures/04_pfc_get_current_config.sql
ALTER PACKAGE pfc_line_of_business COMPILE BODY;
ALTER PACKAGE pfc_value_codes_api COMPILE BODY;
ALTER PACKAGE pfc_remarks_api COMPILE BODY;
ALTER PACKAGE pfc_copy COMPILE BODY;
DECLARE
    l_invalid PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_invalid FROM user_objects
    WHERE object_name IN ('PFC_OPT_PROVIDER_TAXONOMY_ON', 'PFC_OPTION_REGISTRY',
        'PFC_APPLY_OPTION', 'PFC_GET_CURRENT_CONFIG', 'PFC_LINE_OF_BUSINESS',
        'PFC_VALUE_CODES_API', 'PFC_REMARKS_API', 'PFC_COPY')
      AND status <> 'VALID';
    IF l_invalid > 0 THEN
        RAISE_APPLICATION_ERROR(-20996, 'Custom taxonomy or dependent routines failed to compile.');
    END IF;
END;
/
