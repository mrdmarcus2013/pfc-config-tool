WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Installing Remarks structured entry points...
@@../packages/pfc_remarks.pks
SHOW ERRORS PACKAGE pfc_remarks
@@../packages/pfc_remarks.pkb
SHOW ERRORS PACKAGE BODY pfc_remarks
@@../packages/pfc_option_registry.pkb
SHOW ERRORS PACKAGE BODY pfc_option_registry
@@../packages/pfc_remarks_api.pks
SHOW ERRORS PACKAGE pfc_remarks_api
@@../packages/pfc_remarks_api.pkb
SHOW ERRORS PACKAGE BODY pfc_remarks_api

DECLARE
    l_invalid_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_invalid_count
    FROM user_objects
    WHERE object_name IN ('PFC_REMARKS', 'PFC_REMARKS_API',
                          'PFC_OPTION_REGISTRY')
      AND status <> 'VALID';
    IF l_invalid_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20808,
            'The Remarks implementation has invalid objects.');
    END IF;
END;
/
PROMPT Remarks structured entry points installed.
