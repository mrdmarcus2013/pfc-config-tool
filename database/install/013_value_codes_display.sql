WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

PROMPT Installing Value Codes current display metadata without changing configuration data
@@../packages/pfc_value_codes.pkb
@@../packages/pfc_value_codes_api.pkb

DECLARE
    l_errors PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_errors FROM user_errors
    WHERE name IN ('PFC_VALUE_CODES', 'PFC_VALUE_CODES_API') AND type = 'PACKAGE BODY';
    IF l_errors > 0 THEN
        RAISE_APPLICATION_ERROR(-20996, 'Value Codes display package failed to compile.');
    END IF;
END;
/
