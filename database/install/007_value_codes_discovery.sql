WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Installing Value Codes structured entry points...
@@../packages/pfc_value_codes.pks
SHOW ERRORS PACKAGE pfc_value_codes
@@../packages/pfc_value_codes.pkb
SHOW ERRORS PACKAGE BODY pfc_value_codes
@@../packages/pfc_value_codes_api.pks
SHOW ERRORS PACKAGE pfc_value_codes_api
@@../packages/pfc_value_codes_api.pkb
SHOW ERRORS PACKAGE BODY pfc_value_codes_api

DECLARE
    l_invalid_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_invalid_count
    FROM user_objects
    WHERE object_name IN (
        'PFC_VALUE_CODES',
        'PFC_VALUE_CODES_API'
    )
      AND status <> 'VALID';
    IF l_invalid_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20807,
            'The Value Codes implementation has invalid objects.');
    END IF;
END;
/
PROMPT Value Codes structured entry points installed.
