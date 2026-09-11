WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

PROMPT Installing explicit Value Codes controls without reseeding configuration
@@../packages/pfc_value_codes.pks
@@../packages/pfc_value_codes.pkb

ALTER PACKAGE pfc_option_registry COMPILE BODY;
ALTER PROCEDURE pfc_apply_option COMPILE;
ALTER PACKAGE pfc_line_of_business COMPILE BODY;
ALTER PROCEDURE pfc_get_current_config COMPILE;
ALTER PACKAGE pfc_remarks_api COMPILE BODY;
ALTER PACKAGE pfc_copy COMPILE BODY;

@@../packages/pfc_value_codes_api.pks
@@../packages/pfc_value_codes_api.pkb

DECLARE
    l_invalid PLS_INTEGER;
    l_errors PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_invalid FROM user_objects
    WHERE object_name IN ('PFC_VALUE_CODES', 'PFC_VALUE_CODES_API', 'PFC_OPTION_REGISTRY',
        'PFC_APPLY_OPTION', 'PFC_LINE_OF_BUSINESS', 'PFC_GET_CURRENT_CONFIG', 'PFC_REMARKS_API', 'PFC_COPY')
      AND status <> 'VALID';
    SELECT COUNT(*) INTO l_errors FROM user_errors
    WHERE name IN ('PFC_VALUE_CODES', 'PFC_VALUE_CODES_API', 'PFC_OPTION_REGISTRY',
        'PFC_APPLY_OPTION', 'PFC_LINE_OF_BUSINESS', 'PFC_GET_CURRENT_CONFIG', 'PFC_REMARKS_API', 'PFC_COPY');
    IF l_invalid > 0 OR l_errors > 0 THEN
        RAISE_APPLICATION_ERROR(-20996, 'Value Codes controls or dependent routines failed to compile.');
    END IF;
END;
/
